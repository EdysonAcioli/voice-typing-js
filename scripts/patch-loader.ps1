# Gera sherpa-wasm\sherpa-onnx-wasm-main-asr.data (pacote emscripten) a partir
# dos .onnx + tokens.txt baixados, e corrige os offsets no loader JS.
# O loader original espera os arquivos do modelo en (kroko en); este patch
# aponta os offsets para o modelo pt (Kroko pt).
param(
    # raiz do projeto (default: pasta pai do script)
    [string]$Root = ($PSScriptRoot | Split-Path)
)
$ErrorActionPreference = "Stop"

$dest = Join-Path $Root "sherpa-wasm"
$loader = Join-Path $dest "sherpa-onnx-wasm-main-asr.js"
$dataFile = Join-Path $dest "sherpa-onnx-wasm-main-asr.data"

# ordem e offsets do pacote (deve casar com o loader patcheado)
$files = @(
    @{ name = "/.gitignore";       path = $null },
    @{ name = "/README.md";        path = $null },
    @{ name = "/decoder.onnx";     path = Join-Path $dest "decoder.onnx" },
    @{ name = "/encoder.onnx";     path = Join-Path $dest "encoder.onnx" },
    @{ name = "/joiner.onnx";      path = Join-Path $dest "joiner.onnx" },
    @{ name = "/tokens.txt";       path = Join-Path $dest "tokens.txt" }
)

# --- 1. monta o .data (concatenacao crua, alinhada a 4 bytes) ---
$total = 0
foreach ($f in $files) {
    if ($f.path) { $total += (Get-Item $f.path).Length }
}
Write-Host ("montando .data ({0:N1} MB)..." -f ($total/1MB))

$fs = [System.IO.File]::Create($dataFile)
try {
    foreach ($f in $files) {
        if ($f.path) {
            $bytes = [System.IO.File]::ReadAllBytes($f.path)
            $fs.Write($bytes, 0, $bytes.Length)
        }
    }
} finally { $fs.Close() }

# --- 2. calcula offsets reais e corrige o loader ---
$offset = 0
$entries = @()
foreach ($f in $files) {
    $len = 0
    if ($f.path) { $len = (Get-Item $f.path).Length }
    $entries += @{ name = $f.name; start = $offset; end = $offset + $len }
    $offset += $len
}

$js = [System.IO.File]::ReadAllText($loader)
$newFilesBlock = ($entries | ForEach-Object {
    '{filename:"' + $_.name + '",start:' + $_.start + ',end:' + $_.end + '}'
}) -join ","

$pattern = '(?s)files:\[(.*?)\],remote_package_size:\d+'
if ($js -notmatch $pattern) { throw "bloco files:[...] nao encontrado no loader" }
$js = $js -replace $pattern, ("files:[" + $newFilesBlock + "],remote_package_size:" + $total)
[System.IO.File]::WriteAllText($loader, $js)

Write-Host ("OK: .data {0:N0} bytes, loader patcheado" -f $total)
