[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)][string]$BaseUrl,
	[Parameter(Mandatory = $true)][string]$Owner,
	[Parameter(Mandatory = $true)][string]$Repo,
	[Parameter(Mandatory = $true)][string]$Token,
	[Parameter(Mandatory = $true)][string]$Tag,
	[Parameter(Mandatory = $true)][string]$Title,
	[Parameter(Mandatory = $true)][string]$Body,
	[Parameter(Mandatory = $true)][string]$AssetPath,
	[string]$AssetName = "",
	[string]$TargetCommitish = "main",
	[switch]$Prerelease
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ([string]::IsNullOrWhiteSpace($AssetName)) {
	$AssetName = [System.IO.Path]::GetFileName($AssetPath)
}

if (-not (Test-Path -LiteralPath $AssetPath -PathType Leaf)) {
	throw "Asset not found: $AssetPath"
}

$baseApi = ($BaseUrl.TrimEnd("/")) + "/api/v1/repos/$Owner/$Repo"
$headers = @{
	Authorization = "token $Token"
	Accept = "application/json"
}
$jsonHeaders = @{
	Authorization = "token $Token"
	Accept = "application/json"
	"Content-Type" = "application/json"
}

function Get-StatusCode {
	param([System.Management.Automation.ErrorRecord]$ErrorRecord)
	if ($null -eq $ErrorRecord.Exception.Response) {
		return $null
	}
	try {
		return [int]$ErrorRecord.Exception.Response.StatusCode
	} catch {
		return $null
	}
}

function Invoke-JsonRequest {
	param(
		[string]$Method,
		[string]$Uri,
		[object]$BodyObject = $null
	)
	if ($null -eq $BodyObject) {
		return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
	}
	$json = $BodyObject | ConvertTo-Json -Depth 10 -Compress
	return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $jsonHeaders -Body $json
}

$release = $null
$tagUri = "$baseApi/releases/tags/$([System.Uri]::EscapeDataString($Tag))"
try {
	$release = Invoke-JsonRequest -Method Get -Uri $tagUri
} catch {
	$status = Get-StatusCode $_
	if ($status -ne 404) {
		throw
	}
}

$payload = [ordered]@{
	tag_name = $Tag
	target_commitish = $TargetCommitish
	name = $Title
	body = $Body
	prerelease = [bool]$Prerelease
	draft = $false
}

if ($null -eq $release) {
	$release = Invoke-JsonRequest -Method Post -Uri "$baseApi/releases" -BodyObject $payload
} else {
	$release = Invoke-JsonRequest -Method Patch -Uri "$baseApi/releases/$($release.id)" -BodyObject $payload
}

$assets = @()
try {
	$assets = @(Invoke-JsonRequest -Method Get -Uri "$baseApi/releases/$($release.id)/assets")
} catch {
	$status = Get-StatusCode $_
	if ($status -ne 404) {
		throw
	}
}

foreach ($asset in $assets) {
	if ($asset.name -eq $AssetName) {
		Invoke-JsonRequest -Method Delete -Uri "$baseApi/releases/$($release.id)/assets/$($asset.id)" | Out-Null
	}
}

$curl = Get-Command curl.exe -ErrorAction Stop
$uploadUri = "$baseApi/releases/$($release.id)/assets?name=$([System.Uri]::EscapeDataString($AssetName))"
$curlOutput = & $curl.Source `
	-sS `
	-X POST `
	-H "Authorization: token $Token" `
	-H "Accept: application/json" `
	--form ("attachment=@" + $AssetPath) `
	$uploadUri

if ($LASTEXITCODE -ne 0) {
	throw "curl upload failed with exit code $LASTEXITCODE"
}

$attachment = $curlOutput | ConvertFrom-Json
[ordered]@{
	ok = $true
	release_id = $release.id
	release_tag = $release.tag_name
	release_name = $release.name
	release_url = $release.html_url
	asset_name = $attachment.name
	asset_url = $attachment.browser_download_url
} | ConvertTo-Json -Compress
