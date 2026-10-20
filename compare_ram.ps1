# Compara RAM de cada processo Chrome antes/depois de carregar o modelo Whisper
$before = @{}
Get-Content "$env:TEMP\chrome_before.txt" | ForEach-Object {
    $p = $_ -split ' '
    # "267,9" (pt-BR) → 267.9; evita parse como milhar
    $val = [double]($p[1] -replace ',', '.')
    $before[[int]$p[0]] = $val
}

$after = Get-Process chrome | Sort-Object WorkingSet64 -Descending
$totalDelta = 0
foreach ($proc in $after) {
    $b = 0
    if ($before.ContainsKey($proc.Id)) { $b = $before[$proc.Id] }
    $now = [math]::Round($proc.WorkingSet64 / 1MB, 1)
    $delta = [math]::Round($now - $b, 1)
    $totalDelta += $delta
    $mark = ""
    if ($delta -gt 20) { $mark = " <<<< CRESCU (candidato a aba do app)" }
    "{0}  agora {1,8:N1} MB  antes {2,8:N1} MB  delta {3,8:N1} MB{4}" -f $proc.Id, $now, $b, $delta, $mark
}
""
"Delta total de todos os processos chrome: $([math]::Round($totalDelta,1)) MB"
