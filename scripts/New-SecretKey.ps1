$bytes = New-Object byte[] 64
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($bytes)
}
finally {
    $random.Dispose()
}
($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
