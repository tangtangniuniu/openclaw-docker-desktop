param(
    [string]$ClientId = "",
    [string]$ClientSecret = "",
    [string]$Config = "",
    [string]$AccountId = "",
    [int]$TimeoutSeconds = 10,
    [switch]$Json,
    [switch]$Help
)

$DefaultConfig = Join-Path $HOME ".openclaw/openclaw.json"

function Show-Usage {
    @"
Usage:
  pwsh -File scripts/dingtalk-connection-check.ps1 -ClientId <id> -ClientSecret <secret>
  pwsh -File scripts/dingtalk-connection-check.ps1 -Config <openclaw.json>
  pwsh -File scripts/dingtalk-connection-check.ps1 -Config <openclaw.json> -AccountId <id>

Options:
  -ClientId      Explicit DingTalk client ID
  -ClientSecret  Explicit DingTalk client secret
  -Config        Path to openclaw.json (default: ~/.openclaw/openclaw.json)
  -AccountId     Optional DingTalk account ID under channels.dingtalk.accounts
  -TimeoutSeconds  Request timeout seconds (default: 10)
  -Json            Pretty-print sanitized JSON response
  -Help          Show this help
Notes:
- The script inherits proxy settings from environment variables: HTTP_PROXY / HTTPS_PROXY / NO_PROXY.
- For corporate environments, ensure WebSocket/WSS proxies support Upgrade semantics when later testing stream connections.
"@
}

function Mask-Value([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) {
        return ""
    }
    if ($Value.Length -le 8) {
        return "***"
    }
    return "{0}...{1}" -f $Value.Substring(0, 4), $Value.Substring($Value.Length - 4, 4)
}

function Sanitize-Object($Value) {
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        return $Value
    }
    # Explicitly handle arrays/lists (excluding string/hashtable) by visiting each element
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [hashtable])) {
        if ($Value.GetType().IsArray -or ($Value -is [System.Collections.IList])) {
            $items = @()
            foreach ($Item in $Value) {
                $items += (Sanitize-Object $Item)
            }
            return $items
        }
    }

    $result = @{}
    foreach ($Property in $Value.PSObject.Properties) {
        $name = $Property.Name
        $item = $Property.Value
        $lowered = $name.ToLowerInvariant()
        if ($item -is [string] -and @("clientsecret", "access_token", "accesstoken", "ticket", "token") -contains $lowered) {
            $result[$name] = Mask-Value $item
        } elseif ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
            $items = @()
            foreach ($Entry in $item) {
                $items += (Sanitize-Object $Entry)
            }
            $result[$name] = $items
        } elseif ($item -and $item.PSObject.Properties.Name.Count -gt 0) {
            $result[$name] = Sanitize-Object $item
        } else {
            $result[$name] = $item
        }
    }
    return [pscustomobject]$result
}

function Resolve-FromConfig([string]$ConfigPath, [string]$ResolvedAccountId) {
    $expanded = [Environment]::ExpandEnvironmentVariables($ConfigPath)
    if (-not (Test-Path -LiteralPath $expanded)) {
        throw "Config file not found: $expanded"
    }

    $raw = Get-Content -LiteralPath $expanded -Raw | ConvertFrom-Json
    $dingtalk = $raw.channels.dingtalk
    if ($null -eq $dingtalk) {
        throw "channels.dingtalk not found in config"
    }

    $selected = $dingtalk
    $source = "default"

    if (-not [string]::IsNullOrEmpty($ResolvedAccountId)) {
        $accounts = $dingtalk.accounts
        if ($null -eq $accounts -or $null -eq $accounts.$ResolvedAccountId) {
            throw "Account ID '$ResolvedAccountId' not found under channels.dingtalk.accounts"
        }
        $selected = $accounts.$ResolvedAccountId
        $source = "account:$ResolvedAccountId"
    }

    if ([string]::IsNullOrEmpty($selected.clientId) -or [string]::IsNullOrEmpty($selected.clientSecret)) {
        throw "clientId/clientSecret not found in resolved DingTalk config"
    }

    return [pscustomobject]@{
        ClientId = [string]$selected.clientId
        ClientSecret = [string]$selected.clientSecret
        Source = $source
        ConfigPath = $expanded
    }
}

if ($Help) {
    Show-Usage
    exit 0
}

if (($ClientId -and -not $ClientSecret) -or ($ClientSecret -and -not $ClientId)) {
    throw "-ClientId and -ClientSecret must be provided together"
}

$SourceLabel = "args"
if (-not $ClientId -or -not $ClientSecret) {
    if (-not $Config) {
        $Config = $DefaultConfig
    }
    $resolved = Resolve-FromConfig -ConfigPath $Config -ResolvedAccountId $AccountId
    $ClientId = $resolved.ClientId
    $ClientSecret = $resolved.ClientSecret
    $SourceLabel = $resolved.Source
    $Config = $resolved.ConfigPath
}

$payload = @{
    clientId = $ClientId
    clientSecret = $ClientSecret
    subscriptions = @(
        @{
            type = "CALLBACK"
            topic = "/v1.0/im/bot/messages/get"
        }
    )
} | ConvertTo-Json -Depth 5

$statusCode = 0
$bodyObject = $null
try {
    $response = Invoke-WebRequest -Uri "https://api.dingtalk.com/v1.0/gateway/connections/open" -Method POST -ContentType "application/json" -Headers @{ Accept = "application/json" } -Body $payload -TimeoutSec $TimeoutSeconds -ErrorAction Stop
    $statusCode = [int]$response.StatusCode
    if ($response.Content) {
        $bodyObject = $response.Content | ConvertFrom-Json
    }
} catch {
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $rawBody = $reader.ReadToEnd()
        if ($rawBody) {
            try {
                $bodyObject = $rawBody | ConvertFrom-Json
            } catch {
                $bodyObject = [pscustomobject]@{ raw = $rawBody }
            }
        }
    } else {
        $bodyObject = [pscustomobject]@{ error = $_.Exception.Message }
    }
}

$sanitizedBody = Sanitize-Object $bodyObject

Write-Output "DingTalk connection check"
Write-Output "credential_source=$SourceLabel"
if ($Config) {
    Write-Output "config_path=$Config"
}
Write-Output "account_id=$AccountId"
Write-Output "client_id=$(Mask-Value $ClientId)"
Write-Output "http_status=$statusCode"
if ($Json) {
    Write-Output ("response_json={0}" -f (($sanitizedBody | ConvertTo-Json -Depth 10)))
} else {
    Write-Output ("response={0}" -f (($sanitizedBody | ConvertTo-Json -Depth 10 -Compress)))
}

if ($statusCode -eq 200) {
    if ($bodyObject.endpoint) {
        Write-Output "endpoint=$($bodyObject.endpoint)"
    }
    if ($bodyObject.ticket) {
        Write-Output "ticket=$(Mask-Value ([string]$bodyObject.ticket))"
    }
    exit 0
}

exit 1
