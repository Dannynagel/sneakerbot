<#
.SYNOPSIS
    Identify the e-commerce platform and edge bot-mitigation behind a storefront,
    to decide whether an existing SneakerBot module (shopify / demandware) can be
    reused before writing a new one.

.DESCRIPTION
    Two modes:

      1. Live probe (-Url): sends a single GET with a browser User-Agent and
         scans the response headers + body for platform / anti-bot fingerprints.
         Many high-demand sites (e.g. fanatics.com via Akamai) block scripted
         requests at the edge, so this often only tells you "you are blocked".

      2. Offline scan (-HarPath / -HtmlPath): scans a .har or .html file that
         YOU exported from YOUR OWN browser session (DevTools -> Network ->
         right-click -> "Save all as HAR", or "View source" -> save). This is
         the reliable path when the edge blocks scripted requests. For a HAR it
         also lists candidate cart / availability / checkout XHR endpoints — the
         requests you would replicate when building a site module.

    This script only READS and PATTERN-MATCHES. It does not attempt to bypass
    any bot-mitigation, forge sensor data, or solve challenges.

.EXAMPLE
    ./check-platform.ps1 -Url https://www.fanatics.com/

.EXAMPLE
    ./check-platform.ps1 -HarPath ./fanatics.har

.EXAMPLE
    ./check-platform.ps1 -HtmlPath ./product-page.html
#>

[CmdletBinding(DefaultParameterSetName = 'Url')]
param(
    [Parameter(ParameterSetName = 'Url', Mandatory)]
    [string]$Url,

    [Parameter(ParameterSetName = 'Har', Mandatory)]
    [string]$HarPath,

    [Parameter(ParameterSetName = 'Html', Mandatory)]
    [string]$HtmlPath
)

# name -> regex. Matched (case-insensitively) against headers + body text.
$PlatformFingerprints = [ordered]@{
    'Shopify (reuse sites/shopify.js)'        = 'cdn\.shopify\.com|myshopify\.com|ShopifyAnalytics|Shopify\.theme|x-shopify|/cart/add\.js'
    'Demandware / SFCC (reuse sites/demandware.js)' = 'demandware|on/demandware\.store|/dw/|dwfrm_|/api/chk/|dwsecuretoken'
    'Salesforce Commerce (headless)'          = 'salesforce|commercecloud|/mobify/|pwa-kit'
    'Magento'                                 = 'Magento|/static/version\d|mage/cookies|/pub/static/'
    'BigCommerce'                             = 'bigcommerce|/stencil/|cdn11\.bigcommerce'
    'WooCommerce / WordPress'                 = 'woocommerce|wp-content|wc-ajax'
}

$AntiBotFingerprints = [ordered]@{
    'Akamai Bot Manager'   = '_es_/fo/customdeny|akamai|ak_bmsc|_abck|bm_sz|Reference\s*<span id="referenceId"'
    'DataDome'             = 'datadome|dataDomeCaptcha|x-datadome'
    'PerimeterX / HUMAN'   = 'perimeterx|_pxhd|_px3|px-captcha|/_px/'
    'Cloudflare'           = 'cf-ray|__cf_bm|cf-chl|challenge-platform'
    'Imperva / Incapsula'  = 'incap_ses|visid_incap|_Incapsula_'
    'Queue-it waiting room' = 'queue-it\.net|queueittoken|Queue-it'
    'reCAPTCHA'            = 'g-recaptcha|recaptcha/api'
}

function Find-Fingerprints {
    param([string]$Text, [System.Collections.IDictionary]$Set)
    $hits = @()
    foreach ($name in $Set.Keys) {
        if ($Text -match $Set[$name]) { $hits += $name }
    }
    return $hits
}

function Write-Report {
    param([string]$Haystack, [string[]]$Headers)

    Write-Host ''
    Write-Host '=== Platform ===' -ForegroundColor Cyan
    $platforms = Find-Fingerprints -Text $Haystack -Set $PlatformFingerprints
    if ($platforms) { $platforms | ForEach-Object { Write-Host "  [+] $_" -ForegroundColor Green } }
    else { Write-Host '  (no known platform fingerprint found — likely a custom/own platform, or the body was blocked)' -ForegroundColor Yellow }

    Write-Host ''
    Write-Host '=== Edge / anti-bot ===' -ForegroundColor Cyan
    $antibot = Find-Fingerprints -Text $Haystack -Set $AntiBotFingerprints
    if ($antibot) { $antibot | ForEach-Object { Write-Host "  [!] $_" -ForegroundColor Red } }
    else { Write-Host '  (no known anti-bot fingerprint found)' -ForegroundColor Yellow }

    if ($Headers) {
        Write-Host ''
        Write-Host '=== Notable headers ===' -ForegroundColor Cyan
        $Headers | Where-Object { $_ -match '^(server|x-powered-by|via|set-cookie|x-akamai|x-cache|x-datadome)\s*:' } |
            ForEach-Object { Write-Host "  $_" }
    }
}

switch ($PSCmdlet.ParameterSetName) {

    'Url' {
        Write-Host "Probing $Url ..." -ForegroundColor Cyan
        $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
        try {
            $resp = Invoke-WebRequest -Uri $Url -UserAgent $ua -MaximumRedirection 5 -TimeoutSec 25 -ErrorAction Stop
            $status = $resp.StatusCode
        }
        catch {
            $resp = $_.Exception.Response
            if ($resp) { $status = [int]$resp.StatusCode } else { Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red; return }
        }

        $headerLines = @()
        try { $resp.Headers.GetEnumerator() | ForEach-Object { $headerLines += "$($_.Key): $($_.Value)" } } catch {}
        $body = ''
        try { $body = $resp.Content } catch {}

        Write-Host "HTTP $status" -ForegroundColor $(if ($status -ge 400) { 'Red' } else { 'Green' })
        if ($status -ge 400 -or $body -match 'Access Denied|/_es_/fo/customdeny|challenge') {
            Write-Host 'The edge blocked or challenged this scripted request.' -ForegroundColor Yellow
            Write-Host 'Use the offline mode instead: open the site in your browser, export a HAR' -ForegroundColor Yellow
            Write-Host '(DevTools -> Network -> Save all as HAR), then run:' -ForegroundColor Yellow
            Write-Host '  ./check-platform.ps1 -HarPath ./your-export.har' -ForegroundColor Yellow
        }
        Write-Report -Haystack (($headerLines -join "`n") + "`n" + $body) -Headers $headerLines
    }

    'Html' {
        if (-not (Test-Path $HtmlPath)) { Write-Host "File not found: $HtmlPath" -ForegroundColor Red; return }
        $body = Get-Content -Raw -Path $HtmlPath
        Write-Report -Haystack $body -Headers @()
    }

    'Har' {
        if (-not (Test-Path $HarPath)) { Write-Host "File not found: $HarPath" -ForegroundColor Red; return }
        $har = Get-Content -Raw -Path $HarPath | ConvertFrom-Json
        $entries = $har.log.entries

        # Fingerprint against all request URLs + response header names.
        $haystack = ($entries | ForEach-Object {
            $_.request.url
            ($_.response.headers | ForEach-Object { "$($_.name): $($_.value)" })
        }) -join "`n"
        Write-Report -Haystack $haystack -Headers @()

        Write-Host ''
        Write-Host '=== Candidate cart / checkout / availability endpoints ===' -ForegroundColor Cyan
        Write-Host '(these are the XHRs you would replicate when building the site module)'
        $entries |
            Where-Object { $_.request.url -match '(?i)cart|basket|checkout|availability|inventory|add[-_]?to[-_]?bag|/products?/' } |
            ForEach-Object {
                [PSCustomObject]@{
                    Method = $_.request.method
                    Status = $_.response.status
                    Type   = ($_.response.content.mimeType -replace ';.*$', '')
                    Url     = $_.request.url
                }
            } |
            Sort-Object Url -Unique |
            Format-Table -AutoSize -Wrap
    }
}
