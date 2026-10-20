# Gera WAV de teste com voz pt-BR do Windows (SAPI) para validar transcricao offline.
# Uso: powershell -File scripts\gen-test-wav.ps1
Add-Type -AssemblyName System.Speech

$root = $PSScriptRoot | Split-Path
$wav = Join-Path $root "test-audio.wav"

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SetOutputToWaveFile($wav)

# Procura voz pt-BR; usa default se nao houver
$voices = $synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture -like "pt*" }
if ($voices) {
    $synth.SelectVoice($voices[0].VoiceInfo.Name)
    Write-Output "Voz: $($voices[0].VoiceInfo.Name)"
} else {
    Write-Output "Nenhuma voz pt-BR encontrada; usando default"
    $synth.GetInstalledVoices() | ForEach-Object { Write-Output "  disponivel: $($_.VoiceInfo.Name) ($($_.VoiceInfo.Culture))" }
}

$text = "Nao pergunte o que seu pais pode fazer por voce, pergunte o que voce pode fazer por seu pais."
$synth.Speak($text)
$synth.Dispose()

$f = Get-Item $wav
Write-Output ("WAV gerado: {0:N0} bytes" -f $f.Length)
