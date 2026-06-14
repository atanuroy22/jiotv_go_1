# JioTV Go - Continuous M3U8/MPD Playlist Generator (Auto-refresh every 11 hours)

$LOCAL_URL  = "http://localhost:5001"
$PUBLIC_URL = "https://atanu.qzz.io"
$OUT = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "jiotv_playlist_fresh.m3u"
$OUT_MPD = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "jiotv_drm_playlist.m3u"
$REFRESH_HOURS = 11

$ErrorActionPreference = "Stop"

function Generate-Playlist {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Generating Playlists at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    # Check server
    Write-Host "[1/4] Checking JioTV Go..." -NoNewline
    try {
        $c = Invoke-WebRequest -Uri "$LOCAL_URL/" -TimeoutSec 5 -UseBasicParsing
        if ($c.StatusCode -ne 200) { throw "HTTP $($c.StatusCode)" }
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Retrying in 5 minutes..." -ForegroundColor Yellow
        Start-Sleep -Seconds 300
        return $false
    }

    # Fetch channels
    Write-Host "[2/4] Fetching channels..." -NoNewline
    try {
        $r = Invoke-WebRequest -Uri "$LOCAL_URL/channels" -TimeoutSec 60 -UseBasicParsing
        $ch = ($r.Content | ConvertFrom-Json).result | Where-Object { -not $_.isCustom }
        $total = $ch.Count
        Write-Host " $total channels" -ForegroundColor Green
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Retrying in 5 minutes..." -ForegroundColor Yellow
        Start-Sleep -Seconds 300
        return $false
    }

    # Generate M3U
    Write-Host "[3/4] Fetching fresh render URLs..."
    Write-Host ""

    "#EXTM3U" | Out-File -FilePath $OUT -Encoding UTF8
    "#EXTM3U" | Out-File -FilePath $OUT_MPD -Encoding UTF8

    $ok = 0; $err = 0; $drm = 0; $i = 0; $t0 = Get-Date

    foreach ($c in $ch) {
        $i++
        $pct = [math]::Round(($i / $total) * 100)
        $bar = "#" * [math]::Floor($pct / 2) + "-" * (50 - [math]::Floor($pct / 2))

        if ($i -gt 1) {
            $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds / $i * ($total - $i))
            $eta = if ($sec -lt 60) { "${sec}s" } else { "$([math]::Floor($sec/60))m $($sec%60)s" }
        } else { $eta = "..." }

        $cid = $c.channel_id
        $cname = $c.channel_name

        Write-Host "`r  [$bar] $pct% ($i/$total) ETA:$eta - $cname" -NoNewline

        $hlsUrl = $null
        $mpdUrl = $null
        $isDrm = $false

        # Try HLS first
        try {
            $req = [System.Net.HttpWebRequest]::Create("$LOCAL_URL/live/$cid.m3u8")
            $req.Timeout = 5000
            $req.AllowAutoRedirect = $false

            $resp = $req.GetResponse()
            $code = [int]$resp.StatusCode

            if ($code -eq 302 -or $code -eq 301) {
                $loc = $resp.Headers["Location"]
                if ($loc) {
                    if ($loc.StartsWith("/")) {
                        $hlsUrl = "$PUBLIC_URL$loc"
                    } else {
                        $hlsUrl = $loc -replace 'http://localhost:\d+', $PUBLIC_URL
                        $hlsUrl = $hlsUrl -replace 'http://127\.0\.0\.1:\d+', $PUBLIC_URL
                    }
                }
            } elseif ($code -eq 404) {
                # 404 means no HLS stream - likely DRM channel
                $isDrm = $true
            }
            $resp.Close()
        } catch [System.Net.WebException] {
            $wr = $_.Exception.Response
            if ($wr) {
                $code = [int]$wr.StatusCode
                if ($code -eq 302 -or $code -eq 301) {
                    $loc = $wr.Headers["Location"]
                    if ($loc) {
                        if ($loc.StartsWith("/")) {
                            $hlsUrl = "$PUBLIC_URL$loc"
                        } else {
                            $hlsUrl = $loc -replace 'http://localhost:\d+', $PUBLIC_URL
                            $hlsUrl = $hlsUrl -replace 'http://127\.0\.0\.1:\d+', $PUBLIC_URL
                        }
                    }
                } elseif ($code -eq 404) {
                    $isDrm = $true
                }
            }
        } catch {
            # Other errors
        }

        # If HLS failed or is DRM, try MPD
        if ($isDrm -or -not $hlsUrl) {
            try {
                $req = [System.Net.HttpWebRequest]::Create("$LOCAL_URL/mpd/$cid")
                $req.Timeout = 5000
                $req.AllowAutoRedirect = $false

                $resp = $req.GetResponse()
                $code = [int]$resp.StatusCode

                if ($code -eq 200) {
                    # MPD player page exists - this is a DRM channel
                    $mpdUrl = "$PUBLIC_URL/mpd/$cid"
                    $isDrm = $true
                }
                $resp.Close()
            } catch {
                # MPD also failed
            }
        }

        # Write to appropriate file
        $logo = $c.logoUrl
        if ($logo -and -not $logo.StartsWith("http")) { $logo = "$PUBLIC_URL/jtvimage/$logo" }
        $clang = $c.channelLanguageId
        $ccat = $c.channelCategoryId

        if ($isDrm -and $mpdUrl) {
            "#EXTINF:-1 tvg-id=`"$cid`" tvg-name=`"$cname`" tvg-logo=`"$logo`" tvg-language=`"$clang`" tvg-type=`"$ccat`" group-title=`"$ccat`", $cname [DRM]" | Out-File -FilePath $OUT_MPD -Encoding UTF8 -Append
            $mpdUrl | Out-File -FilePath $OUT_MPD -Encoding UTF8 -Append
            $drm++
        } elseif ($hlsUrl) {
            "#EXTINF:-1 tvg-id=`"$cid`" tvg-name=`"$cname`" tvg-logo=`"$logo`" tvg-language=`"$clang`" tvg-type=`"$ccat`" group-title=`"$ccat`", $cname" | Out-File -FilePath $OUT -Encoding UTF8 -Append
            $hlsUrl | Out-File -FilePath $OUT -Encoding UTF8 -Append
            $ok++
        } else {
            $err++
        }
    }

    $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds)

    Write-Host ""
    Write-Host ""
    Write-Host "[4/4] Done! (${elapsed}s)" -ForegroundColor Green
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  HLS: $ok | DRM: $drm | Fail: $err" -ForegroundColor Green
    Write-Host "  Next refresh: $((Get-Date).AddHours($REFRESH_HOURS).ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""

    return $true
}

# Main loop
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  JioTV Go - Continuous Playlist Generator" -ForegroundColor Cyan
Write-Host "  Refresh interval: Every $REFRESH_HOURS hours" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$runCount = 0
while ($true) {
    $runCount++
    Write-Host ""
    Write-Host ">>> Run #$runCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ""

    $success = Generate-Playlist

    if ($success) {
        $nextRun = (Get-Date).AddHours($REFRESH_HOURS)
        $waitSeconds = [math]::Round(($nextRun - (Get-Date)).TotalSeconds)

        Write-Host ""
        Write-Host "Sleeping for $REFRESH_HOURS hours..." -ForegroundColor Yellow
        Write-Host "Next run: $($nextRun.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
        Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
        Write-Host ""

        while ($waitSeconds -gt 0) {
            $hours = [math]::Floor($waitSeconds / 3600)
            $mins = [math]::Floor(($waitSeconds % 3600) / 60)
            $secs = $waitSeconds % 60
            Write-Host "`r  Next refresh in: $($hours)h $($mins)m $($secs)s" -NoNewline -ForegroundColor Gray
            Start-Sleep -Seconds 60
            $waitSeconds -= 60
        }
        Write-Host ""
    } else {
        Write-Host "Retrying in 5 minutes..." -ForegroundColor Yellow
        Start-Sleep -Seconds 300
    }
}
