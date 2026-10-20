# Baixa transformers.js 3.8.1 + ORT WASM + modelo Whisper base (q8) para vendor/
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = "C:\Users\EDYSON ACIOLI\voice-typing-js"
$vendor = Join-Path $root "vendor"
$ort    = Join-Path $vendor "ort-wasm"
$model  = Join-Path $vendor "models\whisper-base"

New-Item -ItemType Directory -Force -Path $vendor, $ort, $model | Out-Null

function Get-File($url, $dest) {
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 0)) {
        Write-Host "OK (ja existe): $dest"
        return
    }
    Write-Host "Baixando: $url"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Host ("OK: {0} ({1:N0} bytes)" -f $dest, (Get-Item $dest).Length)
}

# --- transformers.js (bundle ESM do browser) ---
Get-File "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/transformers.min.js" (Join-Path $vendor "transformers.min.js")

# --- ONNX Runtime WASM (mesma versao embutida no transformers.js 3.8.1) ---
Get-File "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/ort-wasm-simd-threaded.jsep.mjs" (Join-Path $ort "ort-wasm-simd-threaded.jsep.mjs")
Get-File "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/ort-wasm-simd-threaded.jsep.wasm" (Join-Path $ort "ort-wasm-simd-threaded.jsep.wasm")

# --- Modelo Whisper base (multilingue, inclui pt-BR) - pesos q8 ---
$hf = "https://huggingface.co/onnx-community/whisper-base/resolve/main"
Get-File "$hf/config.json"                 (Join-Path $model "config.json")
Get-File "$hf/generation_config.json"      (Join-Path $model "generation_config.json")
Get-File "$hf/preprocessor_config.json"    (Join-Path $model "preprocessor_config.json")
Get-File "$hf/tokenizer.json"              (Join-Path $model "tokenizer.json")
Get-File "$hf/tokenizer_config.json"       (Join-Path $model "tokenizer_config.json")
Get-File "$hf/special_tokens_map.json"     (Join-Path $model "special_tokens_map.json")
Get-File "$hf/onnx/encoder_model_quantized.onnx"        (Join-Path $model "onnx\encoder_model_quantized.onnx")
Get-File "$hf/onnx/decoder_model_merged_quantized.onnx" (Join-Path $model "onnx\decoder_model_merged_quantized.onnx")

Write-Host ""
Write-Host "=== Downloads concluidos ==="
Get-ChildItem -Recurse $vendor -File | ForEach-Object { "{0}  {1:N0} bytes" -f $_.FullName.Replace($root, ""), $_.Length }
