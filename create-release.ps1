$ErrorActionPreference = "Stop"
$input = "protocol=https`nhost=github.com`n"
$result = $input | git credential fill 2>$null
$token = ($result | Select-String "password=(.*)").Matches.Groups[1].Value
if (-not $token) { Write-Error "No token"; exit 1 }
$headers = @{ Authorization = "token $token"; Accept = "application/vnd.github+json" }
$body = Get-Content "./release-notes.json" -Raw
try {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/profzeller/p16-server-setup/releases" -Method Post -Headers $headers -Body $body -ContentType "application/json"
    Write-Host "Release created: $($response.html_url)"
} catch {
    Write-Host "Error: $($_.Exception.Response.StatusCode.value__)"
}
