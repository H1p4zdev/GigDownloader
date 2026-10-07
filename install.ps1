# =====================================================================
#  GigDownloader - Windows installer (PowerShell 5.1+ or PowerShell 7)
# =====================================================================
#  Install / update (paste into PowerShell):
#      irm https://raw.githubusercontent.com/xauusd25/GigDownloader/main/install.ps1 | iex
#
#  Uninstall:
#      $env:GIG_ACTION = 'uninstall'; irm https://raw.githubusercontent.com/xauusd25/GigDownloader/main/install.ps1 | iex
#
#  No admin rights needed. Python, ffmpeg and Deno are installed for you.
#  Running the downloaded file instead?  powershell -ExecutionPolicy Bypass -File .\install.ps1
#  (This file is plain ASCII on purpose, so it works in every PowerShell.)
# =====================================================================

& {
    param([string]$ActionArg)

    $ErrorActionPreference = 'Stop'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    # ------------------------------ Settings ------------------------------
    $Repo    = 'xauusd25/GigDownloader'
    $AppZip  = "https://github.com/$Repo/archive/refs/heads/main.zip"
    $ConfDir = Join-Path $HOME '.gigdownloader'
    $BinDir  = Join-Path $ConfDir 'bin'        # Deno lives here (cookies etc. stay in $ConfDir)
    $ErrLog  = Join-Path $HOME 'gigdownloader_install_error.log'

    $Action = 'install'
    switch -Regex (([string]$ActionArg).ToLower()) {
        '^(uninstall|--uninstall|remove)$' { $Action = 'uninstall' }
        '^(update|--update)$'              { $Action = 'update' }
    }

    # uv puts itself in ~\.local\bin (older versions: ~\.cargo\bin)
    $env:Path = (Join-Path $HOME '.local\bin') + ';' + (Join-Path $HOME '.cargo\bin') + ';' + $env:Path

    # Progress state shared with the helper functions
    $St = @{ Step = 0; Total = 1; Rc = ''; Notes = (New-Object System.Collections.ArrayList) }

    # ------------------------- Console capabilities -----------------------
    function Enable-Vt {
        try {
            if (-not ('GigNative.Console' -as [type])) {
                Add-Type -Namespace GigNative -Name Console -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
            }
            $h = [GigNative.Console]::GetStdHandle(-11)
            [uint32]$mode = 0
            if (-not [GigNative.Console]::GetConsoleMode($h, [ref]$mode)) { return $false }
            return [GigNative.Console]::SetConsoleMode($h, ($mode -bor 4))
        } catch {
            return $false
        }
    }

    function U([int]$Code) { return [string][char]$Code }

    $esc      = U 27
    $UseColor = $false
    try { $UseColor = [bool](Enable-Vt) } catch { }
    if (-not $UseColor -and $env:WT_SESSION) { $UseColor = $true }      # Windows Terminal always understands ANSI
    if ($PSVersionTable.PSVersion.Major -ge 7) { $UseColor = $true }    # PowerShell 7 handles it too

    if ($UseColor) {
        $N      = $esc + '[0m'
        $R      = $esc + '[1;38;5;196m'
        $G      = $esc + '[1;38;5;82m'
        $Y      = $esc + '[1;38;5;220m'
        $C      = $esc + '[1;38;5;51m'
        $W      = $esc + '[1;38;5;255m'
        $GRAY   = $esc + '[38;5;244m'
        $LAV    = $esc + '[1;38;5;183m'
        $SHADOW = $esc + '[0;38;5;99m'
        $TEAL   = $esc + '[1;38;5;80m'
        $ClrLine = "`r" + $esc + '[K'
    } else {
        $N = ''; $R = ''; $G = ''; $Y = ''; $C = ''; $W = ''; $GRAY = ''; $LAV = ''; $SHADOW = ''; $TEAL = ''
        $ClrLine = "`r" + (' ' * 70) + "`r"
    }

    # Symbols (built from code points so this file stays ASCII)
    $CHK    = U 0x2714      # check mark
    $CROSS  = U 0x2718      # cross
    $WARN   = U 0x26A0      # warning sign
    $DOT    = U 0x25CF      # bullet
    $ARROW  = U 0x25B8      # small arrow
    $PLAY   = U 0x25B6      # play arrow
    $BAR_ON  = U 0x25B0
    $BAR_OFF = U 0x25B1
    $RULE   = U 0x2501
    $VBAR   = U 0x2503
    $TOPL   = U 0x250F
    $BOTL   = U 0x2517
    $BLOCK  = U 0x2588
    $Frames = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { U $_ })

    # GIG logo: '#' = full block, a..f = box-drawing pieces
    $LogoEnc = @(
        ' ######a ##a ######a '
        '##bccccf ##d##bccccf '
        '##d  ###a##d##d  ###a'
        '##d   ##d##d##d   ##d'
        'e######bf##de######bf'
        ' ecccccf ecf ecccccf '
    )
    $Map = @{ '#' = (U 0x2588); 'a' = (U 0x2557); 'b' = (U 0x2554); 'c' = (U 0x2550); 'd' = (U 0x2551); 'e' = (U 0x255A); 'f' = (U 0x255D) }

    # ------------------------------ Helpers -------------------------------
    function Expand-Logo([string]$Line) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $Line.ToCharArray()) {
            $k = [string]$ch
            if ($Map.ContainsKey($k)) { [void]$sb.Append($Map[$k]) } else { [void]$sb.Append($k) }
        }
        return $sb.ToString()
    }

    function Get-Cols {
        try {
            $w = $Host.UI.RawUI.WindowSize.Width
            if ($w -gt 0) { return [int]$w }
        } catch { }
        return 80
    }

    function Get-MiniBar([int]$Done) {
        $s = ''
        for ($i = 1; $i -le $St.Total; $i++) {
            if ($i -le $Done) { $s += $BAR_ON } else { $s += $BAR_OFF }
        }
        return $s
    }

    function Show-Rule([int]$Width, [string]$Color) {
        Write-Host ($Color + ($RULE * $Width) + $N)
    }

    function Show-Header {
        $cols = Get-Cols
        try { Clear-Host } catch { }
        Write-Host ''
        if ($cols -ge 22) {
            $pad = ' ' * [Math]::Max(0, [int][Math]::Floor(($cols - 21) / 2))
            foreach ($l in $LogoEnc) {
                $line = (Expand-Logo $l).Replace($BLOCK, $LAV + $BLOCK + $SHADOW)
                Write-Host ($pad + $SHADOW + $line + $N)
            }
            $sub  = 'Downloader Installer'
            $pad2 = ' ' * [Math]::Max(0, [int][Math]::Floor(($cols - $sub.Length) / 2))
            Write-Host ($pad2 + $TEAL + $sub + $N)
        } else {
            Write-Host ($LAV + 'GigDownloader' + $N + ' ' + $TEAL + 'Installer' + $N)
        }
        Write-Host ''
    }

    function Show-Box([string]$Title, [string[]]$Lines, [string]$Color) {
        Write-Host (' ' + $Color + $VBAR + ' ' + $WARN + ' ' + $Title + $N)
        Write-Host (' ' + $Color + $VBAR + $N)
        foreach ($l in $Lines) { Write-Host (' ' + $Color + $VBAR + $N + ' ' + $l) }
        Write-Host ''
    }

    function Show-Done([string]$Msg) {
        $St.Step++
        Write-Host (' ' + $G + $CHK + $N + ' ' + $G + (Get-MiniBar $St.Step) + $N + ' ' + $Msg)
    }

    function Show-Skip([string]$Msg) {
        $St.Step++
        Write-Host (' ' + $Y + $WARN + $N + ' ' + $Y + (Get-MiniBar $St.Step) + $N + ' ' + $Msg)
    }

    # Runs $Work in a background job with a spinner; aborts the installer on failure.
    function Invoke-Step([string]$Msg, [scriptblock]$Work, [object[]]$WorkArgs = @()) {
        $St.Step++
        $start = Get-Date
        $job = Start-Job -ScriptBlock $Work -ArgumentList $WorkArgs
        $i = 0
        $out = @()
        $failed = $false
        $reason = ''
        try {
            while ($job.State -eq 'Running' -or $job.State -eq 'NotStarted') {
                $frame = $Frames[$i % $Frames.Count]
                Write-Host -NoNewline ($ClrLine + ' ' + $C + $frame + $N + ' ' + $GRAY + (Get-MiniBar ($St.Step - 1)) + $N + ' ' + $W + $Msg + $N)
                $i++
                Start-Sleep -Milliseconds 100
            }
            $out = @(Receive-Job -Job $job -ErrorAction SilentlyContinue | ForEach-Object { "$_" })
            if ($job.State -ne 'Completed') {
                $failed = $true
                try { $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message } catch { }
            }
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }

        $secs = [int]((Get-Date) - $start).TotalSeconds
        if (-not $failed) {
            Write-Host ($ClrLine + ' ' + $G + $CHK + $N + ' ' + $G + (Get-MiniBar $St.Step) + $N + ' ' + $Msg + ' ' + $GRAY + "${secs}s" + $N)
            return
        }

        Write-Host ($ClrLine + ' ' + $R + $CROSS + $N + ' ' + $R + (Get-MiniBar ($St.Step - 1)) + $N + ' ' + $R + $Msg + $N)
        Write-Host ''
        Write-Host (' ' + $R + $TOPL + ($RULE * 2) + ' Error details ' + ($RULE * 14) + $N)
        $tail = @($out)
        if ($reason) { $tail += $reason }
        $tail = @($tail | Select-Object -Last 15)
        foreach ($l in $tail) { Write-Host (' ' + $R + $VBAR + $N + ' ' + $l) }
        Write-Host (' ' + $R + $BOTL + ($RULE * 30) + $N)
        try { Set-Content -Path $ErrLog -Value (@($out) + @($reason)) -Encoding UTF8 } catch { }
        Write-Host ''
        Write-Host (' ' + $Y + 'Full log saved: ' + $N + $W + $ErrLog + $N)
        Write-Host ''
        throw 'GIG_ABORT'
    }

    function Read-Choice {
        try {
            if (-not [Environment]::UserInteractive) { return '1' }
            $reply = Read-Host
            if ([string]::IsNullOrWhiteSpace($reply)) { return '1' }
            return $reply.Trim()
        } catch {
            return '1'
        }
    }

    # Puts uv's tool folder (where gig.exe lives) on the user PATH and on this session's PATH.
    function Add-ToolBinToPath {
        $bin = ''
        try { $bin = ((& uv tool dir --bin) | Out-String).Trim() } catch { }
        if (-not $bin) { $bin = Join-Path $HOME '.local\bin' }

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($null -eq $userPath) { $userPath = '' }
        $present = $false
        foreach ($p in ($userPath -split ';')) {
            if ($p -and ($p.TrimEnd('\') -ieq $bin.TrimEnd('\'))) { $present = $true }
        }
        if (-not $present) {
            if ($userPath) { $newPath = $bin + ';' + $userPath } else { $newPath = $bin }
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        }

        $sessionHas = $false
        foreach ($p in ($env:Path -split ';')) {
            if ($p -and ($p.TrimEnd('\') -ieq $bin.TrimEnd('\'))) { $sessionHas = $true }
        }
        if (-not $sessionHas) { $env:Path = $bin + ';' + $env:Path }
    }

    # ---------------------------- Step scripts ----------------------------
    $UvWork = {
        $ErrorActionPreference = 'Continue'
        $ProgressPreference = 'SilentlyContinue'
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            $env:UV_NO_MODIFY_PATH = '1'
            Invoke-RestMethod -UseBasicParsing -Uri 'https://astral.sh/uv/install.ps1' | Invoke-Expression
            $env:Path = (Join-Path $HOME '.local\bin') + ';' + (Join-Path $HOME '.cargo\bin') + ';' + $env:Path
        }
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { throw 'uv was not found after installing it' }
        & uv --version
    }

    $AppWork = {
        param($Zip)
        $ErrorActionPreference = 'Continue'
        & uv tool install --force --reinstall --python 3.12 --with 'yt-dlp[default]' --with imageio-ffmpeg "gigdownloader @ $Zip" 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { throw "uv tool install failed (exit code $LASTEXITCODE)" }
    }

    $DenoWork = {
        param($Url, $Dest)
        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'SilentlyContinue'
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('gig_deno_' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $zip = Join-Path $tmp 'deno.zip'
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $zip
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null
            Expand-Archive -Path $zip -DestinationPath $Dest -Force
            $exe = Join-Path $Dest 'deno.exe'
            if (-not (Test-Path $exe)) { throw 'deno.exe was not found in the download' }
            & $exe --version
        } finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    $UninstallWork = {
        $ErrorActionPreference = 'Continue'
        if (Get-Command uv -ErrorAction SilentlyContinue) {
            & uv tool uninstall gigdownloader 2>&1 | ForEach-Object { "$_" }
        }
    }

    # ------------------------------- Main ---------------------------------
    $oldEnc = $null
    try {
        try { $oldEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
        try { [Console]::CursorVisible = $false } catch { }

        Show-Header

        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Show-Box 'This installer is for Windows' @('On Linux, macOS or Termux use install.sh instead.') $Y
            return
        }

        # Already installed? Offer reinstall / uninstall (like the Termux installer)
        if ($Action -eq 'install') {
            $existing = Get-Command gig -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host (' ' + $GRAY + $DOT + $N + ' GigDownloader is already installed at ' + $W + $existing.Source + $N)
                Write-Host -NoNewline (' Choose an action: ' + $C + '[1]' + $N + ' Reinstall/Update  ' + $C + '[2]' + $N + ' Uninstall  ' + $C + '[3]' + $N + ' Exit: ')
                try { [Console]::CursorVisible = $true } catch { }
                $choice = Read-Choice
                try { [Console]::CursorVisible = $false } catch { }
                switch ($choice) {
                    '2' { $Action = 'uninstall' }
                    '3' { Write-Host ''; return }
                    default { $Action = 'update' }
                }
                Write-Host ''
            }
        }

        $sw = [Diagnostics.Stopwatch]::StartNew()

        if ($Action -eq 'uninstall') {
            $St.Total = 2
            Invoke-Step 'Removing GigDownloader' $UninstallWork
            if (Test-Path $BinDir) { Remove-Item -Recurse -Force $BinDir -ErrorAction SilentlyContinue }
            Show-Done 'Removed Deno'
            Write-Host ''
            Show-Rule 45 $G
            Write-Host (' ' + $G + $CHK + ' GigDownloader removed' + $N)
            Show-Rule 45 $G
            Write-Host ''
            Write-Host (' ' + $GRAY + 'Your downloads (GigVideos / GigAudios) and ~\.gigdownloader\cookies.txt were left untouched.' + $N)
            Write-Host ''
            return
        }

        # ---- install / update ----
        $St.Total = 4
        Invoke-Step 'Installing uv (Python manager)' $UvWork
        Invoke-Step 'Installing GigDownloader' $AppWork @($AppZip)

        $denoOnPath = Get-Command deno -ErrorAction SilentlyContinue
        $denoLocal  = Test-Path (Join-Path $BinDir 'deno.exe')
        $arch = $env:PROCESSOR_ARCHITECTURE
        if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
        if ($denoOnPath -or $denoLocal) {
            Show-Done 'Deno already installed'
        } elseif ($arch -ne 'AMD64' -and $arch -ne 'ARM64') {
            Show-Skip 'Deno skipped (unsupported system) - YouTube needs Node.js 22+'
            [void]$St.Notes.Add('No Deno build for this system. For full YouTube quality install Node.js 22 or newer.')
        } else {
            $denoUrl = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
            Invoke-Step 'Installing Deno (YouTube engine)' $DenoWork @($denoUrl, $BinDir)
        }

        Add-ToolBinToPath
        Show-Done 'Command added: gig'

        $sw.Stop()
        $ruleW = [Math]::Min(45, (Get-Cols))
        Write-Host ''
        Show-Rule $ruleW $G
        Write-Host (' ' + $G + $CHK + ' Installation completed successfully' + $N + '  ' + $GRAY + '(' + [int]$sw.Elapsed.TotalSeconds + 's)' + $N)
        Show-Rule $ruleW $G
        Write-Host ''
        Write-Host (' ' + $Y + $PLAY + ' Start it by typing:' + $N)
        Write-Host ('   ' + $C + 'gig' + $N)
        Write-Host ''
        Write-Host (' ' + $GRAY + 'Also available:' + $N + ' gigdownloader ' + [string][char]0x00B7 + ' gig --check ' + [string][char]0x00B7 + ' gig --help')
        foreach ($note in $St.Notes) {
            Write-Host ''
            Write-Host (' ' + $Y + $ARROW + $N + ' ' + $note)
        }
        Write-Host ''
    } catch {
        if ($_.Exception.Message -ne 'GIG_ABORT') {
            Write-Host ''
            Write-Host (' ' + $R + $CROSS + ' Unexpected error: ' + $_.Exception.Message + $N)
            Write-Host ''
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
        if ($oldEnc) { try { [Console]::OutputEncoding = $oldEnc } catch { } }
    }
} $(if ($args.Count -gt 0) { [string]$args[0] } else { [string]$env:GIG_ACTION })
