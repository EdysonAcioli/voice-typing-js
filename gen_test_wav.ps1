# Gera WAV de teste com voz pt-BR do Windows (SAPI) para validar transcrição offline.
Add-Type -AssemblyName System.Speech

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SetOutputToWaveFile("C:\Users\EDYSON ACIOLI\voice-typing-js\test-audio.wav")

# Procura voz pt-BR; usa default se não houver
$voices = $synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture -like "pt*" }
if ($voices) {
    $synth.SelectVoice($voices[0].VoiceInfo.Name)
    Write-Output "Voz: $($voices[0].VoiceInfo.Name)"
} else {
    Write-Output "Nenhuma voz pt-BR encontrada; usando default"
    $synth.GetInstalledVoices() | ForEach-Object { Write-Output "  disponivel: $($_.VoiceInfo.Name) ($($_.VoiceInfo.Culture))" }
}

$text = "Este e um teste de digitacao por voz funcionando totalmente offline no navegador."
$synth.Speak($text)
$synth.Dispose()

$f = Get-Item "C:\Users\EDYSON ACIOLI\voice-typing-js\test-audio.wav"
Write-Output ("WAV gerado: {0:N0} bytes" -f $f.Length)
