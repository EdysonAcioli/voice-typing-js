# Baixa os binarios do reconhecedor sherpa-onnx WASM (streaming Zipformer pt).
# Fonte: Hugging Face kouhxp/sherpa-onnx-streaming-zipformer-pt-kroko
# + build oficial sherpa-onnx v1.13.5 (wasm, single-thread SIMD).
#
# Uso:  powershell -File scripts\download-model.ps1
# Requer: ~170 MB de disco em sherpa-wasm\
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root  = $PSScriptRoot | Split-Path
$dest  = Join-Path $root "sherpa-wasm"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Get-File($url, $destFile) {
    if ((Test-Path $destFile) -and ((Get-Item $destFile).Length -gt 0)) {
        Write-Host "  OK (ja existe): $(Split-Path $destFile -Leaf)" -ForegroundColor DarkGray
        return
    }
    Write-Host "  baixando $(Split-Path $destFile -Leaf) ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $destFile -UseBasicParsing
    Write-Host "  OK: $(Split-Path $destFile -Leaf) ($('{0:N1}' -f ((Get-Item $destFile).Length/1MB)) MB)" -ForegroundColor Green
}

# --- sherpa-onnx WASM (API JS + loader + wasm) ---
# O tarball en-asr-zipformer traz o build WASM oficial (loader + API + wasm);
# o .data (modelo en) é descartado — o patch-loader.ps1 gera o nosso .data pt.
$gh = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.5/sherpa-onnx-wasm-simd-v1.13.5-en-asr-zipformer.tar.bz2"
Write-Host "`n[1/3] sherpa-onnx WASM (API JS + loader)" -ForegroundColor Yellow
$tmp = Join-Path $env:TEMP ("sherpa-wasm-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$tbz = Join-Path $tmp "wasm.tar.bz2"
Get-File $gh $tbz
tar -xjf $tbz -C $tmp
$src = Get-ChildItem $tmp -Recurse -Filter "sherpa-onnx-wasm-main-asr.js" | Select-Object -First 1
if (-not $src) { throw "loader nao encontrado no tarball" }
Copy-Item $src.FullName (Join-Path $dest "sherpa-onnx-wasm-main-asr.js") -Force
$api = Get-ChildItem $tmp -Recurse -Filter "sherpa-onnx-asr.js" | Select-Object -First 1
if ($api) { Copy-Item $api.FullName (Join-Path $dest "sherpa-onnx-asr.js") -Force }
$wasm = Get-ChildItem $tmp -Recurse -Filter "sherpa-onnx-wasm-main-asr.wasm" | Select-Object -First 1
if ($wasm) { Copy-Item $wasm.FullName (Join-Path $dest "sherpa-onnx-wasm-main-asr.wasm") -Force }
Remove-Item -Recurse -Force $tmp

# --- Modelo Zipformer streaming pt (transdutor, 155 MB) ---
$hf = "https://huggingface.co/kouhxp/sherpa-onnx-streaming-zipformer-pt-kroko/resolve/main"
Write-Host "`n[2/3] Modelo Zipformer streaming pt (Kroko)" -ForegroundColor Yellow
Get-File "$hf/encoder.onnx"     (Join-Path $dest "encoder.onnx")
Get-File "$hf/decoder.onnx"     (Join-Path $dest "decoder.onnx")
Get-File "$hf/joiner.onnx"      (Join-Path $dest "joiner.onnx")
Get-File "$hf/tokens.txt"       (Join-Path $dest "tokens.txt")

# --- Empacota os .onnx + tokens no formato .data do emscripten ---
# O loader espera um unico arquivo .data com offsets fixos; o script
# scripts\patch-loader.ps1 gera o .data e corrige os offsets no loader.
Write-Host "`n[3/3] Empacotando modelo em sherpa-onnx-wasm-main-asr.data" -ForegroundColor Yellow
& (Join-Path $PSScriptRoot "patch-loader.ps1")

Write-Host "`nPronto! Rode: python server.py  ->  http://localhost:8765" -ForegroundColor Green
