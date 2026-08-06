$script:StartupLog = Join-Path $env:TEMP "REVS-SS-TOOL-startup.log"
try {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] starting $PSCommandPath" | Set-Content -LiteralPath $script:StartupLog -Encoding UTF8
} catch {}

if ($PSCommandPath) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($PSCommandPath -and ([Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA" -or -not $isAdmin)) {
    $quotedPath = '"' + $PSCommandPath + '"'
    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-STA","-File",$quotedPath)
    if ($isAdmin) {
        Start-Process powershell.exe -ArgumentList $args
    } else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    }
    exit
}

$ErrorActionPreference = "Stop"
trap {
    $msg = $_ | Out-String
    try { $msg | Add-Content -LiteralPath $script:StartupLog -Encoding UTF8 } catch {}
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("REVS SS TOOL could not start.`n`n$msg`nLog: $script:StartupLog", "REVS SS TOOL startup error", "OK", "Error") | Out-Null
    } catch {
        Write-Error $msg
    }
    exit 1
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installDir = "$env:USERPROFILE\Downloads\RevsSSTool"

# Registry
# UI
$RegSearchRoots = @(
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer",
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags",
    "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
    "HKCU\Software\Microsoft\Command Processor",
    "HKCU\Environment",
    "HKLM\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings",
    "HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR",
    "HKLM\SYSTEM\MountedDevices",
    "HKLM\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Reports
$RelayUrl = if ($env:SS_RELAY_URL) { $env:SS_RELAY_URL.Trim() } else { "" }
$RelayKey = if ($env:SS_RELAY_KEY) { $env:SS_RELAY_KEY.Trim() } else { "" }
$WebhookUrls = @()
if ($RelayUrl -and $RelayUrl -ne ("__RELAY" + "_URL__")) { $WebhookUrls += $RelayUrl }
if ($env:SS_WEBHOOK_URL)  { $WebhookUrls += $env:SS_WEBHOOK_URL }
if ($env:SS_WEBHOOK_URLS) { $WebhookUrls += ($env:SS_WEBHOOK_URLS -split ",") }
$WebhookUrls = @($WebhookUrls | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$reportingOffValues = @("0", "false", "off", "no")
$reportingEnv = if ($env:SS_REPORTING) { $env:SS_REPORTING.Trim().ToLowerInvariant() } else { "" }
$reportingForcedOff = $reportingOffValues -contains $reportingEnv -or $env:SS_REPORTING_DISABLED -eq "1"
$script:ReportingState = [hashtable]::Synchronized(@{ Enabled = [bool]($WebhookUrls.Count -gt 0 -and -not $reportingForcedOff) })

# UI
# Group

$ToolData = @(
    @{ Name="PrefetchView";          Desc="Shows which programs were opened and when";              Group="Program history"; Type="Web";    URL="https://github.com/Orbdiff/PrefetchView/releases/download/v1.6.7/pv++.exe" },
    @{ Name="BAMReveal";             Desc="Shows a list of apps that recently ran";                 Group="Program history"; Type="GitHub"; URL="https://github.com/Orbdiff/BAMReveal/releases/latest" },
    @{ Name="BAM-parser";            Desc="Another view of programs that ran, with times";          Group="Program history"; Type="GitHub"; URL="https://github.com/spokwn/BAM-parser/releases/latest" },
    @{ Name="BamDeletedKeys";        Desc="Finds run-history entries someone tried to delete";      Group="Program history"; Type="GitHub"; URL="https://github.com/spokwn/BamDeletedKeys/releases/latest" },
    @{ Name="pcasvc-executed";       Desc="Yet another record of programs that ran";                Group="Program history"; Type="GitHub"; URL="https://github.com/spokwn/pcasvc-executed/releases/latest" },
    @{ Name="process-parser";        Desc="Reads records of programs that were running";            Group="Program history"; Type="GitHub"; URL="https://github.com/spokwn/process-parser/releases/latest" },
    @{ Name="prefetch-parser";       Desc="Shows which programs were opened and when";              Group="Program history"; Type="GitHub"; URL="https://github.com/spokwn/prefetch-parser/releases/latest" },
    @{ Name="ActivitiesCache";       Desc="Shows a timeline of recent activity";                    Group="Program history"; Type="GitHub"; URL="https://github.com/spokwn/ActivitiesCache-execution/releases/latest" },
    @{ Name="UserAssistView";        Desc="Shows programs you clicked and how often";               Group="Program history"; Type="GitHub"; URL="https://github.com/Orbdiff/UserAssistView/releases/latest" },
    @{ Name="AmcacheParser";         Desc="Lists programs Windows keeps a record of";               Group="Program history"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/AmcacheParser.zip" },
    @{ Name="ExecutedProgramsList";  Desc="Lists programs that have been run";                       Group="Program history"; Type="Web";    URL="https://www.nirsoft.net/utils/executedprogramslist.zip" },
    @{ Name="PECmd";                 Desc="Shows which programs ran (command line)";                 Group="Program history"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/PECmd.zip" },
    @{ Name="WinPrefetchView";       Desc="Shows which programs were opened and when";              Group="Program history"; Type="Web";    URL="https://www.nirsoft.net/utils/winprefetchview.zip" },
    @{ Name="RecentFileCacheParser"; Desc="Reads an old list of recently run programs";             Group="Program history"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/RecentFileCacheParser.zip" },
    @{ Name="ComputerActivityView";  Desc="Shows a timeline of what the PC did";                     Group="Program history"; Type="Web";    URL="https://www.nirsoft.net/utils/computer_activity_view.html" },

    @{ Name="MeowClientsFucker";     Desc="Detects known Minecraft cheat clients";                  Group="Cheat detection"; Type="GitHub"; URL="https://github.com/MeowTonynoh/MeowClientFucker/releases/latest" },
    @{ Name="MeowDoomsdayFucker";    Desc="Detects the Doomsday cheat";                             Group="Cheat detection"; Type="GitHub"; URL="https://github.com/MeowTonynoh/MeowDoomsdayFucker/releases/latest" },
    @{ Name="MeowNovowareFucker";    Desc="Detects the Novoware cheat";                             Group="Cheat detection"; Type="GitHub"; URL="https://github.com/MeowTonynoh/MeowNovowareFucker/releases/latest" },
    @{ Name="DQRKIS-FUCKER";         Desc="Detects the DQRKIS cheat";                               Group="Cheat detection"; Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/cheesecatlol/DQRKIS-FUCKER/refs/heads/main/DqrkisFucker.ps1')" },
    @{ Name="MeowModAnalyzer";       Desc="Checks Minecraft mods for cheat code";                   Group="Cheat detection"; Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/MeowTonynoh/MeowModAnalyzer/main/MeowModAnalyzer.ps1')" },
    @{ Name="RL ModAnalyzer";        Desc="Checks Minecraft mods for cheat code";                   Group="Cheat detection"; Type="GitHub"; URL="https://github.com/ItzIceHere/RedLotus-Mod-Analyzer/releases/latest" },
    @{ Name="InjGen";                Desc="Detects cheats injected into Java/Minecraft";            Group="Cheat detection"; Type="GitHub"; URL="https://github.com/Orbdiff/InjGen/releases/latest" },
    @{ Name="Fileless";              Desc="Looks for cheats that hide in memory, not on disk";      Group="Cheat detection"; Type="GitHub"; URL="https://github.com/Orbdiff/Fileless/releases/latest" },
    @{ Name="MeowImportsChecker";    Desc="Checks a program for suspicious components";             Group="Cheat detection"; Type="GitHub"; URL="https://github.com/MeowTonynoh/MeowImportsChecker/releases/latest" },
    @{ Name="MeowResolver";          Desc="Un-hides scrambled text inside programs";                Group="Cheat detection"; Type="GitHub"; URL="https://github.com/MeowTonynoh/MeowResolver/releases/latest" },
    @{ Name="StringsParser";         Desc="Scans a file for hidden text and bad patterns";          Group="Cheat detection"; Type="GitHub"; URL="https://github.com/Orbdiff/StringsParser/releases/latest" },

    @{ Name="Jarabel";               Desc="Finds Minecraft .jar files on the PC";                   Group="Minecraft files"; Type="GitHub"; URL="https://github.com/nay-cat/Jarabel/releases/latest" },
    @{ Name="JARParser";             Desc="Finds and inspects Minecraft cheat .jar files";          Group="Minecraft files"; Type="GitHub"; URL="https://github.com/Orbdiff/JARParser/releases/latest" },
    @{ Name="Luyten";                Desc="Opens Java files so you can read the code";              Group="Minecraft files"; Type="GitHub"; URL="https://github.com/deathmarine/Luyten/releases/latest" },
    @{ Name="DIE-engine";            Desc="Tells you what a file really is";                        Group="Minecraft files"; Type="Web";    URL="https://github.com/horsicq/DIE-engine/releases" },
    @{ Name="HxD";                   Desc="Opens any file to inspect its raw bytes";                Group="Minecraft files"; Type="Link";   URL="https://mh-nexus.de/en/hxd/" },
    @{ Name="bstrings";              Desc="Searches a file for text using patterns";                Group="Minecraft files"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/bstrings.zip" },

    @{ Name="MacroDetector";         Desc="Looks for auto-clicker / macro software";                Group="Macros & input";  Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/NiccBlahh/MacroDetector/refs/heads/main/MacroDetector.ps1')" },
    @{ Name="PSHunter";              Desc="Looks for suspicious PowerShell usage";                  Group="Macros & input";  Type="GitHub"; URL="https://github.com/praiselily/PSHunter/releases/latest" },

    @{ Name="USBDeview";             Desc="Lists every USB device ever plugged in";                 Group="Devices & drives"; Type="Web";    URL="https://www.nirsoft.net/utils/usbdeview.zip" },
    @{ Name="USBDetector";           Desc="Shows USB sticks that were plugged in";                  Group="Devices & drives"; Type="GitHub"; URL="https://github.com/Orbdiff/USBDetector/releases/latest" },
    @{ Name="HarddiskConverter";     Desc="Translates drive IDs so they're readable";              Group="Devices & drives"; Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/HarddiskConverter.ps1')" },
    @{ Name="NTFS Parser";           Desc="Reads low-level drive records (advanced)";               Group="Devices & drives"; Type="GitHub"; URL="https://github.com/thewhiteninja/ntfstool/releases/latest" },
    @{ Name="MFTECmd";               Desc="Reads the drive's file table (advanced)";                Group="Devices & drives"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/MFTECmd.zip" },
    @{ Name="AlternateStreamView";   Desc="Reveals data hidden inside files";                       Group="Devices & drives"; Type="Web";    URL="https://www.nirsoft.net/utils/alternatestreamview.zip" },

    @{ Name="JournalParser";         Desc="Shows recent file changes on the drive";                 Group="File activity";   Type="GitHub"; URL="https://github.com/Orbdiff/JournalParser/releases/latest" },
    @{ Name="JournalTrace";          Desc="Tracks recent file activity on the drive";               Group="File activity";   Type="GitHub"; URL="https://github.com/spokwn/JournalTrace/releases/latest" },
    @{ Name="CheckDeletedUSN";       Desc="Finds files deleted since the PC turned on";             Group="File activity";   Type="GitHub"; URL="https://github.com/Orbdiff/CheckDeletedUSN/releases/latest" },
    @{ Name="PathsParser";           Desc="Lists where programs were run from";                     Group="File activity";   Type="GitHub"; URL="https://github.com/spokwn/PathsParser/releases/latest" },
    @{ Name="OpenSaveFilesView";     Desc="Shows files opened or saved via dialogs";                Group="File activity";   Type="Web";    URL="https://www.nirsoft.net/utils/opensavefilesview.zip" },
    @{ Name="JumpListsView";         Desc="Shows recent and frequent files";                        Group="File activity";   Type="Web";    URL="https://www.nirsoft.net/utils/jumplistsview.zip" },
    @{ Name="JumpListExplorer";      Desc="Shows recently opened files, with a window";             Group="File activity";   Type="Web";    URL="https://download.ericzimmermanstools.com/net9/JumpListExplorer.zip" },
    @{ Name="JLECmd";                Desc="Reads recent-file shortcuts (command line)";             Group="File activity";   Type="Web";    URL="https://download.ericzimmermanstools.com/net9/JLECmd.zip" },
    @{ Name="ShellBagsView";         Desc="Shows folders that were opened before";                  Group="File activity";   Type="Web";    URL="https://www.nirsoft.net/utils/shellbagsview.zip" },
    @{ Name="ShellBagsExplorer";     Desc="Shows folders that were opened before";                  Group="File activity";   Type="Web";    URL="https://download.ericzimmermanstools.com/net9/ShellBagsExplorer.zip" },
    @{ Name="CommonDirectories";     Desc="Lists files in folders cheats often hide in";            Group="File activity";   Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/CommonDirectories.ps1')" },
    @{ Name="Everything";            Desc="Instantly search every file by name";                    Group="File activity";   Type="Link";   URL="https://www.voidtools.com/downloads/" },
    @{ Name="RecentFileCacheParser2";Desc="Reads an old list of recently run programs";             Group="File activity";   Type="Web";    URL="https://download.ericzimmermanstools.com/net9/RecentFileCacheParser.zip" },

    @{ Name="AltDetector";           Desc="Looks for signs of alternate accounts";                  Group="Accounts & network"; Type="GitHub"; URL="https://github.com/praiselily/AltDetector/releases/latest" },
    @{ Name="RL AltChecker";         Desc="Looks for signs of alternate accounts";                  Group="Accounts & network"; Type="GitHub"; URL="https://github.com/ItzIceHere/RedLotusAltChecker/releases/latest" },
    @{ Name="WeHateFakers";          Desc="Checks phone-hotspot / tethering history";               Group="Accounts & network"; Type="Cmd";    Command="iwr https://raw.githubusercontent.com/praiselily/WeHateFakers/refs/heads/main/HotspotLogs.ps1 | iex" },
    @{ Name="NetworkUsageView";      Desc="Shows how much network each app used";                   Group="Accounts & network"; Type="Web";    URL="https://www.nirsoft.net/utils/networkusageview.zip" },
    @{ Name="BrowserDownloadsView";  Desc="Lists everything downloaded in browsers";                Group="Accounts & network"; Type="Web";    URL="https://www.nirsoft.net/utils/browserdownloadsview.zip" },
    @{ Name="VMAware";               Desc="Checks if the PC is a virtual machine";                  Group="Accounts & network"; Type="GitHub"; URL="https://github.com/kernelwernel/VMAware/releases/latest" },

    @{ Name="Services";              Desc="Lists background services running on the PC";            Group="System & tasks";  Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Services.ps1')" },
    @{ Name="SignedScheduledTasks";  Desc="Finds odd or unsigned scheduled tasks";                  Group="System & tasks";  Type="Cmd";    Command="Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Signed-Scheduled-Tasks.ps1')" },
    @{ Name="RL TaskSentinel";       Desc="Watches scheduled tasks for anything odd";               Group="System & tasks";  Type="GitHub"; URL="https://github.com/ItzIceHere/RedLotus-Task-Sentinel/releases/latest" },
    @{ Name="TaskSchedulerView";     Desc="Shows all scheduled tasks and history";                  Group="System & tasks";  Type="Web";    URL="https://www.nirsoft.net/utils/taskschedulerview.zip" },
    @{ Name="SystemInformer";        Desc="A powerful Task Manager replacement";                    Group="System & tasks";  Type="Link";   URL="https://www.systeminformer.com/canary" },
    @{ Name="PFTrace";               Desc="Checks if system tools were used to run cheats";         Group="System & tasks";  Type="GitHub"; URL="https://github.com/Orbdiff/PFTrace/releases/latest" },
    @{ Name="DPS-Analyzer";          Desc="Checks a system memory area for tampering";              Group="System & tasks";  Type="GitHub"; URL="https://github.com/Orbdiff/DPS-Analyzer/releases/latest" },
    @{ Name="KernelLiveDumpTool";    Desc="Takes a snapshot of system memory (advanced)";           Group="System & tasks";  Type="GitHub"; URL="https://github.com/spokwn/KernelLiveDumpTool/releases/latest" },

    @{ Name="FullEventLogView";      Desc="Shows all Windows event log entries";                    Group="Logs & timeline"; Type="Web";    URL="https://www.nirsoft.net/utils/fulleventlogview.zip" },
    @{ Name="Hayabusa";              Desc="Builds a fast timeline from event logs";                 Group="Logs & timeline"; Type="GitHub"; URL="https://github.com/Yamato-Security/hayabusa/releases/latest" },
    @{ Name="SrumECmd";              Desc="Shows app and network usage history";                    Group="Logs & timeline"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/SrumECmd.zip" },
    @{ Name="TimelineExplorer";      Desc="Opens the result tables these tools make";               Group="Logs & timeline"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/TimelineExplorer.zip" },
    @{ Name="RegistryExplorer";      Desc="Browse the Windows registry in a window";                Group="Logs & timeline"; Type="Web";    URL="https://download.ericzimmermanstools.com/net9/RegistryExplorer.zip" },
    @{ Name="RegScanner";            Desc="Search the registry with a window (easy)";               Group="Logs & timeline"; Type="Web";    URL="https://www.nirsoft.net/utils/regscanner.zip" },
    @{ Name="Velociraptor";          Desc="Deep investigation tool (advanced)";                     Group="Logs & timeline"; Type="GitHub"; URL="https://github.com/Velocidex/velociraptor/releases/latest" },
    @{ Name="Espouken Tool";         Desc="All-in-one screenshare checker";                         Group="Logs & timeline"; Type="GitHub"; URL="https://github.com/spokwn/Tool/releases/latest" },

    @{ Name="NET 9.0";               Desc="Runtime some tools need to work";                        Group="Runtimes";        Type="Web";    URL="https://download.visualstudio.microsoft.com/download/pr/92dba916-bc51-4e76-8b0e-d41d37ce5fa4/ab08f3e95bf7a3d3da336a7e8c8eca63/dotnet-sdk-9.0.203-win-x64.exe" },
    @{ Name="NET 10.0";              Desc="Runtime some tools need to work";                        Group="Runtimes";        Type="Web";    URL="https://download.visualstudio.microsoft.com/download/pr/b3f93f0e-9e5e-4b4c-a4c4-36db0c4b0e3e/dotnet-runtime-10.0.0-win-x64.exe" },
    @{ Name="VSRedist";              Desc="Runtime some tools need to work";                        Group="Runtimes";        Type="Web";    URL="https://aka.ms/vs/17/release/vc_redist.x64.exe" }
)

# UI

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="REVS SS TOOL"
    Width="1180" Height="720"
    MinWidth="1180" MinHeight="720"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    FontFamily="Segoe UI"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True"
    TextOptions.TextFormattingMode="Display"
    TextOptions.TextRenderingMode="ClearType"
    RenderOptions.ClearTypeHint="Enabled">

    <Window.Resources>
        <SolidColorBrush x:Key="Bg" Color="#191919"/>
        <SolidColorBrush x:Key="Top" Color="#202020"/>
        <SolidColorBrush x:Key="Panel" Color="#242424"/>
        <SolidColorBrush x:Key="Panel2" Color="#2B2B2B"/>
        <SolidColorBrush x:Key="Hover" Color="#333333"/>
        <SolidColorBrush x:Key="Pressed" Color="#3B3B3B"/>
        <SolidColorBrush x:Key="Line" Color="#3A3A3A"/>
        <SolidColorBrush x:Key="LineSoft" Color="#2F2F2F"/>
        <SolidColorBrush x:Key="Ink" Color="#F5F5F5"/>
        <SolidColorBrush x:Key="Muted" Color="#C8C8C8"/>
        <SolidColorBrush x:Key="Faint" Color="#9A9A9A"/>
        <SolidColorBrush x:Key="Blue" Color="#4CC9F0"/>
        <SolidColorBrush x:Key="SevCritical" Color="#F87171"/>
        <SolidColorBrush x:Key="SevHigh" Color="#FB923C"/>
        <SolidColorBrush x:Key="SevMedium" Color="#FBBF24"/>
        <SolidColorBrush x:Key="SevLow" Color="#60A5FA"/>
        <SolidColorBrush x:Key="SevClean" Color="#34D399"/>
        <SolidColorBrush x:Key="BgGrad" Color="#242424"/>
        <SolidColorBrush x:Key="TopGrad" Color="#202020"/>
        <SolidColorBrush x:Key="BlueGrad" Color="#0F6CBD"/>

        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="8"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0"/></Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border CornerRadius="4" Background="#565656" Margin="2,1"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0"/></Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="WinBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource Muted}"/>
            <Setter Property="Width" Value="46"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="{StaticResource Hover}"/>
                                <Setter Property="Foreground" Value="{StaticResource Ink}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Background" Value="{StaticResource Pressed}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="CloseWinBtn" TargetType="Button" BasedOn="{StaticResource WinBtn}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="0,7,0,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#C42B1C"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#A71D11"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" CornerRadius="6" Background="{StaticResource BlueGrad}" Padding="14,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Opacity" Value="0.92"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Background" Value="{StaticResource Pressed}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="b" Property="Background" Value="#2A2A2A"/>
                                <Setter Property="Foreground" Value="{StaticResource Faint}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ToolRow" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Width" Value="326"/>
            <Setter Property="Height" Value="92"/>
            <Setter Property="Margin" Value="0,0,14,14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="row" CornerRadius="8" Background="{StaticResource Panel2}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="11">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="row" Property="Background" Value="{StaticResource Hover}"/>
                                <Setter TargetName="row" Property="BorderBrush" Value="#4A4A4A"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="row" Property="BorderBrush" Value="{StaticResource Blue}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="row" Property="Background" Value="{StaticResource Pressed}"/>
                                <Setter TargetName="row" Property="BorderBrush" Value="#555555"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="row" Property="Opacity" Value="0.55"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border x:Name="MainShell" Background="{StaticResource BgGrad}" BorderBrush="{StaticResource LineSoft}" BorderThickness="1" CornerRadius="7">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="38"/>
                <RowDefinition Height="104"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="34"/>
            </Grid.RowDefinitions>

            <Grid x:Name="TitleBar" Grid.Row="0" Background="{StaticResource TopGrad}">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                    <TextBlock Text="&#x2726;" Foreground="{StaticResource Muted}" FontSize="13" VerticalAlignment="Center"/>
                    <TextBlock Text="REVS" Foreground="{StaticResource Ink}" FontWeight="Bold" FontSize="11" Margin="10,0,4,0" VerticalAlignment="Center"/>
                    <TextBlock Text="by revsies" Foreground="{StaticResource Faint}" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
                    <Button x:Name="MinBtn" Style="{StaticResource WinBtn}" Content="&#xE921;"/>
                    <Button x:Name="CloseBtn" Style="{StaticResource CloseWinBtn}" Content="&#xE8BB;"/>
                </StackPanel>
            </Grid>

            <Grid Grid.Row="1" Margin="26,0,24,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="360"/>
                </Grid.ColumnDefinitions>
                <Border Width="54" Height="54" CornerRadius="9" Background="{StaticResource BlueGrad}" VerticalAlignment="Center">
                    <TextBlock Text="&#x25C7;" FontSize="34" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="16,0,0,0">
                    <TextBlock x:Name="PageTitle" Text="REVS SS TOOL" FontSize="27" FontWeight="Bold" Foreground="{StaticResource Ink}"/>
                    <TextBlock Text="Search, scan, download, and launch every tool from one page." FontSize="12.5" Foreground="{StaticResource Muted}" Margin="1,4,0,0"/>
                </StackPanel>
                <Border Grid.Column="2" x:Name="SearchBorder" CornerRadius="8" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="38" VerticalAlignment="Center">
                    <Grid>
                        <TextBlock Text="&#x2315;" FontSize="16" Foreground="{StaticResource Faint}" Margin="12,0,0,0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="SearchHint" Text="Search everything..." FontSize="13" Foreground="{StaticResource Faint}" VerticalAlignment="Center" Margin="38,0,0,0" IsHitTestVisible="False"/>
                        <TextBox x:Name="SearchBox" Background="Transparent" BorderThickness="0" Foreground="{StaticResource Ink}" CaretBrush="{StaticResource Blue}" FontSize="13" VerticalContentAlignment="Center" Margin="38,0,12,0"/><TextBlock x:Name="CountBadge" Visibility="Collapsed"/>
                    </Grid>
                </Border>
            </Grid>

            <Grid Grid.Row="2" Margin="26,0,16,0">
                <ScrollViewer x:Name="PageTools" VerticalScrollBarVisibility="Auto" Padding="0,0,10,0">
                    <StackPanel>
                        <Border CornerRadius="8" Background="{StaticResource Panel2}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="18,15" Margin="0,0,14,16">
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <StackPanel>
                                    <TextBlock Text="Automatic PC check" FontSize="17" FontWeight="SemiBold" Foreground="{StaticResource Ink}"/>
                                    <TextBlock x:Name="AutoHint" Text="Runs every built-in module in forensic order, scores what it finds and writes a report." FontSize="11.5" Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
                                    <TextBlock x:Name="AutoProgress" Text="" FontFamily="Consolas" FontSize="11" Foreground="{StaticResource Blue}" Margin="0,7,0,0"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                                    <Button x:Name="ReportBtn" Style="{StaticResource PrimaryBtn}" Content="Open report" Height="40" Width="120" Margin="0,0,10,0" Visibility="Collapsed"/>
                                    <Button x:Name="FullBtn" Style="{StaticResource PrimaryBtn}" Content="Run full check" Height="40" Width="150"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <Border x:Name="ResultsCard" Visibility="Collapsed" CornerRadius="8" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="18,15" Margin="0,0,14,16">
                            <StackPanel>
                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                    <Border x:Name="VerdictChip" CornerRadius="6" Padding="12,6" Background="{StaticResource SevClean}" VerticalAlignment="Center">
                                        <TextBlock x:Name="VerdictText" Text="CLEAN" FontSize="13" FontWeight="Bold" Foreground="#101010"/>
                                    </Border>
                                    <TextBlock x:Name="VerdictDetail" Grid.Column="1" Text="" FontSize="12" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="12,0,0,0" TextWrapping="Wrap"/>
                                    <TextBlock x:Name="ScoreText" Grid.Column="2" Text="" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource Faint}" VerticalAlignment="Center"/>
                                </Grid>
                                <ScrollViewer MaxHeight="360" VerticalScrollBarVisibility="Auto">
                                    <StackPanel x:Name="FindingsPanel"/>
                                </ScrollViewer>
                            </StackPanel>
                        </Border>

                        <TextBlock Text="Built-in scans" FontSize="17" FontWeight="SemiBold" Foreground="{StaticResource Ink}" Margin="0,0,0,10"/>
                        <WrapPanel x:Name="ScanCardPanel" Margin="0,0,0,16">
                            <Border Width="326" Height="118" CornerRadius="8" Background="{StaticResource Panel2}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="12" Margin="0,0,14,14">
                                <Grid>
                                    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="38"/></Grid.RowDefinitions>
                                    <StackPanel Orientation="Horizontal">
                                        <Border Width="32" Height="32" CornerRadius="6" Background="{StaticResource BlueGrad}"><TextBlock Text="&#x25A3;" FontSize="18" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                                        <StackPanel Margin="10,0,0,0">
                                            <TextBlock Text="Registry search" FontSize="12.5" FontWeight="Bold" Foreground="{StaticResource Ink}"/>
                                            <TextBlock Text="Search Windows evidence locations by keyword" FontSize="11" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Width="240" Margin="0,3,0,0"/>
                                        </StackPanel>
                                    </StackPanel>
                                    <Grid Grid.Row="1">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="78"/></Grid.ColumnDefinitions>
                                        <Border x:Name="ScanBorder" CornerRadius="6" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,0,8,0">
                                            <Grid>
                                                <TextBlock x:Name="ScanHint" Text="usb, cheat name..." Foreground="{StaticResource Faint}" FontSize="11" VerticalAlignment="Center" Margin="10,0,0,0" IsHitTestVisible="False"/>
                                                <TextBox x:Name="ScanBox" Background="Transparent" BorderThickness="0" Foreground="{StaticResource Ink}" CaretBrush="{StaticResource Blue}" FontSize="11" VerticalContentAlignment="Center" Margin="9,0,6,0"/>
                                            </Grid>
                                        </Border>
                                        <Button x:Name="ScanBtn" Grid.Column="1" Style="{StaticResource PrimaryBtn}" Content="Search"/>
                                    </Grid>
                                </Grid>
                            </Border>
                            <Button x:Name="JavaBtn" Style="{StaticResource ToolRow}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="32" Height="32" CornerRadius="6" Background="{StaticResource BlueGrad}"><TextBlock Text="&#x2615;" FontSize="19" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="Running programs" FontSize="12.5" FontWeight="Bold" Foreground="{StaticResource Ink}"/><TextBlock Text="Find Java and .jar processes" FontSize="11" Foreground="{StaticResource Muted}" Margin="0,3,0,0"/><TextBlock Text="Built-in" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource Blue}" Margin="0,7,0,0"/></StackPanel></Grid></Button>
                            <Button x:Name="ModBtn" Style="{StaticResource ToolRow}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="32" Height="32" CornerRadius="6" Background="{StaticResource BlueGrad}"><TextBlock Text="&#x25A7;" FontSize="18" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="Injected mods" FontSize="12.5" FontWeight="Bold" Foreground="{StaticResource Ink}"/><TextBlock Text="Inspect Minecraft mod jars" FontSize="11" Foreground="{StaticResource Muted}" Margin="0,3,0,0"/><TextBlock Text="Built-in" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource Blue}" Margin="0,7,0,0"/></StackPanel></Grid></Button>
                            <Button x:Name="ModFolderBtn" Style="{StaticResource ToolRow}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="32" Height="32" CornerRadius="6" Background="{StaticResource BlueGrad}"><TextBlock Text="&#xE8B7;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="Paste mod folder path" FontSize="12.5" FontWeight="Bold" Foreground="{StaticResource Ink}"/><TextBlock x:Name="ModFolderStatus" Text="Only this folder will be scanned" FontSize="11" Foreground="{StaticResource Muted}" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/><TextBlock Text="Required for jars" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource Blue}" Margin="0,7,0,0"/></StackPanel></Grid></Button>
                        </WrapPanel>
                        <StackPanel x:Name="ListPanel"/>
                    </StackPanel>
                </ScrollViewer>
                <StackPanel x:Name="EmptyState" Visibility="Collapsed" VerticalAlignment="Top" HorizontalAlignment="Center" Margin="0,120,0,0">
                    <TextBlock Text="&#x2315;" FontSize="34" HorizontalAlignment="Center" Foreground="{StaticResource Faint}"/>
                    <TextBlock x:Name="EmptyText" Text="No tools match your search." FontSize="13" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" Margin="0,10,0,0"/>
                </StackPanel>
                <Button x:Name="NavScan" Visibility="Collapsed"/>
                <Button x:Name="NavTools" Visibility="Collapsed"/>
                <Border x:Name="PageScan" Visibility="Collapsed"/>
            </Grid>

            <Border Grid.Row="3" Background="{StaticResource Top}" CornerRadius="0,0,7,7" BorderBrush="{StaticResource LineSoft}" BorderThickness="0,1,0,0">
                <Grid Margin="26,0,18,0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <Border x:Name="StatusDot" Width="8" Height="8" CornerRadius="4" Background="#34D399" VerticalAlignment="Center"/>
                    <TextBlock x:Name="StatusLine" Grid.Column="1" Text="Ready." FontFamily="Consolas" FontSize="11" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="10,0,0,0" TextTrimming="CharacterEllipsis"/>
                    <CheckBox x:Name="ReportingToggle" Grid.Column="2" Content="Reporting" FontSize="10.5" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                    <TextBlock x:Name="HookBadge" Grid.Column="3" Text="" FontSize="10.5" Foreground="{StaticResource Faint}" VerticalAlignment="Center"/>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@

$script:MotionEnabled = $env:REVS_REDUCED_MOTION -ne "1"
$global:REVS_MotionEnabled = $script:MotionEnabled

function global:New-FluentAnimation {
    param([double]$To, [int]$Ms = 180, [int]$Delay = 0)
    $anim = New-Object Windows.Media.Animation.DoubleAnimation
    $anim.To = $To
    $anim.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($Ms))
    if ($Delay -gt 0) { $anim.BeginTime = [TimeSpan]::FromMilliseconds($Delay) }
    $ease = New-Object Windows.Media.Animation.CubicEase
    $ease.EasingMode = [Windows.Media.Animation.EasingMode]::EaseOut
    $anim.EasingFunction = $ease
    return $anim
}

function global:Enable-FluentMotion {
    param($Control, [double]$HoverScale = 1.015, [double]$PressScale = 0.975)
    if (-not $Control -or -not $global:REVS_MotionEnabled) { return }
    $Control.RenderTransformOrigin = "0.5,0.5"
    $scale = New-Object Windows.Media.ScaleTransform
    $Control.RenderTransform = $scale
    $Control.Add_MouseEnter({
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (global:New-FluentAnimation $HoverScale 140))
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (global:New-FluentAnimation $HoverScale 140))
    }.GetNewClosure())
    $Control.Add_MouseLeave({
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (global:New-FluentAnimation 1 160))
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (global:New-FluentAnimation 1 160))
    }.GetNewClosure())
    $Control.Add_PreviewMouseLeftButtonDown({
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (global:New-FluentAnimation $PressScale 80))
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (global:New-FluentAnimation $PressScale 80))
    }.GetNewClosure())
    $Control.Add_PreviewMouseLeftButtonUp({
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (global:New-FluentAnimation $HoverScale 120))
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (global:New-FluentAnimation $HoverScale 120))
    }.GetNewClosure())
}

function global:Start-FluentReveal {
    param($Element, [int]$Delay = 0, [double]$FromY = 10)
    if (-not $Element) { return }
    if (-not $global:REVS_MotionEnabled) { $Element.Opacity = 1; return }
    $Element.Opacity = 0
    $Element.RenderTransform = New-Object Windows.Media.TranslateTransform 0, $FromY
    $Element.BeginAnimation([Windows.UIElement]::OpacityProperty, (global:New-FluentAnimation 1 260 $Delay))
    $Element.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (global:New-FluentAnimation 0 320 $Delay))
}

function global:Set-FluentBorderColor {
    param($Border, [string]$Hex, [int]$Ms = 180)
    if (-not $Border) { return }
    $color = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    if (-not $global:REVS_MotionEnabled) {
        $Border.BorderBrush = New-Object Windows.Media.SolidColorBrush $color
        return
    }
    $brush = $Border.BorderBrush
    if (-not ($brush -is [Windows.Media.SolidColorBrush]) -or $brush.IsFrozen) {
        $brush = New-Object Windows.Media.SolidColorBrush $color
        $Border.BorderBrush = $brush
    }
    $anim = New-Object Windows.Media.Animation.ColorAnimation
    $anim.To = $color
    $anim.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($Ms))
    $ease = New-Object Windows.Media.Animation.CubicEase
    $ease.EasingMode = [Windows.Media.Animation.EasingMode]::EaseOut
    $anim.EasingFunction = $ease
    $brush.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty, $anim)
}

# UI
[xml]$disclaimerXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="REVS SS TOOL" Width="560" Height="430"
    WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
    WindowStyle="None" AllowsTransparency="True" Background="Transparent" FontFamily="Segoe UI"
    UseLayoutRounding="True" SnapsToDevicePixels="True"
    TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType"
    RenderOptions.ClearTypeHint="Enabled">
    <Window.Resources>
        <SolidColorBrush x:Key="BgGrad" Color="#242424"/>
        <SolidColorBrush x:Key="TopGrad" Color="#202020"/>
        <SolidColorBrush x:Key="BlueGrad" Color="#0F6CBD"/>
        <Style x:Key="DlgBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Height" Value="42"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.9"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="#3B3B3B"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border x:Name="DisclaimerShell" Background="{StaticResource BgGrad}" BorderBrush="#2F2F2F" BorderThickness="1" CornerRadius="8">
        <Grid>
            <Grid.RowDefinitions><RowDefinition Height="38"/><RowDefinition Height="*"/><RowDefinition Height="70"/></Grid.RowDefinitions>
            <Grid Grid.Row="0" Background="{StaticResource TopGrad}">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                    <TextBlock Text="&#x2726;" Foreground="#C8C8C8" FontSize="13" VerticalAlignment="Center"/>
                    <TextBlock Text="REVS" Foreground="#F5F5F5" FontWeight="Bold" FontSize="11" Margin="10,0,4,0" VerticalAlignment="Center"/>
                    <TextBlock Text="by revsies" Foreground="#9A9A9A" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
            <Grid Grid.Row="1" Margin="30,26,30,10">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <StackPanel Orientation="Horizontal">
                    <Border Width="54" Height="54" CornerRadius="9" Background="{StaticResource BlueGrad}">
                        <TextBlock Text="&#x25C7;" FontSize="34" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel Margin="16,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="REVS SS TOOL" FontSize="25" FontWeight="Bold" Foreground="#F5F5F5"/>
                        <TextBlock Text="Read this before launching" FontSize="12.5" Foreground="#C8C8C8" Margin="1,4,0,0"/>
                    </StackPanel>
                </StackPanel>
                <StackPanel Grid.Row="1" Margin="0,28,0,0">
                    <Border CornerRadius="8" Background="#2B2B2B" BorderBrush="#3A3A3A" BorderThickness="1" Padding="14" Margin="0,0,0,10">
                        <TextBlock TextWrapping="Wrap" Foreground="#DCDCDC" FontSize="13" LineHeight="20" Text="Tools download from their official pages into one temporary folder. Closing the app stops launched tools where possible and wipes the downloaded folder."/>
                    </Border>
                    <Border CornerRadius="8" Background="#2B2B2B" BorderBrush="#3A3A3A" BorderThickness="1" Padding="14" Margin="0,0,0,10">
                        <TextBlock TextWrapping="Wrap" Foreground="#DCDCDC" FontSize="13" LineHeight="20" Text="If reporting is configured, this launcher posts clicked tools and scan summaries to your configured endpoint. It does not read passwords or personal files."/>
                    </Border>
                    <TextBlock TextWrapping="Wrap" Foreground="#A6A6A6" FontSize="12.5" LineHeight="19" Text="Bundled tools are maintained by their own authors. REVS only downloads and opens them."/>
                </StackPanel>
            </Grid>
            <Grid Grid.Row="2" Margin="30,0,30,24" VerticalAlignment="Bottom">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Button x:Name="CancelBtn" Grid.Column="0" Style="{StaticResource DlgBtn}" Content="Cancel" Background="#2B2B2B" Foreground="#C8C8C8" BorderBrush="#3A3A3A" BorderThickness="1"/>
                <Button x:Name="AcceptBtn" Grid.Column="2" Style="{StaticResource DlgBtn}" Content="Accept" Background="{StaticResource BlueGrad}" Foreground="#FFFFFF" FontWeight="SemiBold" BorderThickness="0"/>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

$disclaimerWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $disclaimerXaml))
$DisclaimerShell = $disclaimerWindow.FindName("DisclaimerShell")
$AcceptBtn = $disclaimerWindow.FindName("AcceptBtn")
$CancelBtn = $disclaimerWindow.FindName("CancelBtn")
$disclaimerWindow.Add_Loaded({ Start-FluentReveal $DisclaimerShell 0 8 })
Enable-FluentMotion $AcceptBtn 1.018 0.975
Enable-FluentMotion $CancelBtn 1.012 0.98
$disclaimerWindow.Add_MouseLeftButtonDown({ try { $disclaimerWindow.DragMove() } catch {} })
$script:disclaimerAccepted = $false
$AcceptBtn.Add_Click({ $script:disclaimerAccepted = $true;  $disclaimerWindow.Close() })
$CancelBtn.Add_Click({ $script:disclaimerAccepted = $false; $disclaimerWindow.Close() })
$disclaimerWindow.ShowDialog() | Out-Null
if (-not $script:disclaimerAccepted) { exit }

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$MinBtn     = $window.FindName("MinBtn")
$CloseBtn   = $window.FindName("CloseBtn")
$TitleBar   = $window.FindName("TitleBar")
$SearchBox  = $window.FindName("SearchBox")
$SearchHint = $window.FindName("SearchHint")
$CountBadge = $window.FindName("CountBadge")
$ScanBox    = $window.FindName("ScanBox")
$ScanHint   = $window.FindName("ScanHint")
$ScanBtn    = $window.FindName("ScanBtn")
$JavaBtn    = $window.FindName("JavaBtn")
$ModBtn     = $window.FindName("ModBtn")
$ModFolderBtn = $window.FindName("ModFolderBtn")
$ModFolderStatus = $window.FindName("ModFolderStatus")
$ListPanel  = $window.FindName("ListPanel")
$StatusLine = $window.FindName("StatusLine")
$StatusDot  = $window.FindName("StatusDot")
$HookBadge  = $window.FindName("HookBadge")
$ReportingToggle = $window.FindName("ReportingToggle")
$SearchBorder = $window.FindName("SearchBorder")
$ScanBorder   = $window.FindName("ScanBorder")
$EmptyState   = $window.FindName("EmptyState")
$EmptyText    = $window.FindName("EmptyText")
$NavScan   = $window.FindName("NavScan")
$NavTools  = $window.FindName("NavTools")
$PageScan  = $window.FindName("PageScan")
$PageTools = $window.FindName("PageTools")
$PageTitle = $window.FindName("PageTitle")
$MainShell = $window.FindName("MainShell")
$FullBtn       = $window.FindName("FullBtn")
$ReportBtn     = $window.FindName("ReportBtn")
$AutoProgress  = $window.FindName("AutoProgress")
$ResultsCard   = $window.FindName("ResultsCard")
$FindingsPanel = $window.FindName("FindingsPanel")
$VerdictChip   = $window.FindName("VerdictChip")
$VerdictText   = $window.FindName("VerdictText")
$VerdictDetail = $window.FindName("VerdictDetail")
$ScoreText     = $window.FindName("ScoreText")
$ScanCardPanel = $window.FindName("ScanCardPanel")

Enable-FluentMotion $MinBtn 1.04 0.92
Enable-FluentMotion $CloseBtn 1.04 0.92
Enable-FluentMotion $ScanBtn 1.02 0.97
Enable-FluentMotion $JavaBtn 1.015 0.975
Enable-FluentMotion $ModBtn 1.015 0.975
Enable-FluentMotion $ModFolderBtn 1.015 0.975
Enable-FluentMotion $FullBtn 1.02 0.97
Enable-FluentMotion $ReportBtn 1.02 0.97

# UI
$navActive   = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString("#FFFFFF26"))
$navInactive = [Windows.Media.Brushes]::Transparent
function Show-Page {
    param([string]$page)
    $PageTools.Visibility = "Visible"
    $PageScan.Visibility = "Collapsed"
    $PageTitle.Text = "REVS SS TOOL"
}
$NavScan.Add_Click({  Show-Page "scan" })
$NavTools.Add_Click({ Show-Page "tools" })

# UI
$SearchBox.Add_GotFocus({  Set-FluentBorderColor $SearchBorder "#4CC9F0" 160 })
$SearchBox.Add_LostFocus({ Set-FluentBorderColor $SearchBorder "#3A3A3A" 180 })
$ScanBox.Add_GotFocus({    Set-FluentBorderColor $ScanBorder "#4CC9F0" 160 })
$ScanBox.Add_LostFocus({   Set-FluentBorderColor $ScanBorder "#3A3A3A" 180 })

# Helpers

function Write-Log {
    param([string]$msg)
    $time = Get-Date -Format "HH:mm:ss"
    $StatusLine.Dispatcher.Invoke([Action]{ $StatusLine.Text = "[$time] $msg" })
}

function Set-Status {
    param($msg, $state = "busy")   # Status
    $StatusLine.Dispatcher.Invoke([Action]{
        $StatusLine.Text = $msg
        $c = switch ($state) { "ok" { "#34D399" } "err" { "#F87171" } default { "#3B82F6" } }
        $StatusDot.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($c)))
    })
}

function Update-ReportingUi {
    if (-not $ReportingToggle -or -not $HookBadge) { return }
    $ReportingToggle.Dispatcher.Invoke([Action]{
        $hasEndpoint = [bool]($WebhookUrls.Count -gt 0)
        $ReportingToggle.IsEnabled = $hasEndpoint
        $ReportingToggle.IsChecked = [bool]$script:ReportingState.Enabled
        $HookBadge.Text = if (-not $hasEndpoint) {
            "reporting unavailable"
        } elseif ($script:ReportingState.Enabled) {
            "reporting on"
        } else {
            "reporting off"
        }
    })
}

$script:SelectedModFolder = $null
function Select-ModFolder {
    param([switch]$Optional)
    $defaultPath = ""
    if ($script:SelectedModFolder -and (Test-Path -LiteralPath $script:SelectedModFolder)) {
        $defaultPath = $script:SelectedModFolder
    } elseif ($env:APPDATA -and (Test-Path -LiteralPath (Join-Path $env:APPDATA ".minecraft\mods"))) {
        $defaultPath = Join-Path $env:APPDATA ".minecraft\mods"
    } elseif ($env:APPDATA -and (Test-Path -LiteralPath (Join-Path $env:APPDATA "ModrinthApp\profiles"))) {
        $defaultPath = Join-Path $env:APPDATA "ModrinthApp\profiles"
    }

    try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch {}
    $path = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Paste the full mods/profile folder path to scan. Example: C:\Users\you\AppData\Roaming\ModrinthApp\profiles\name\mods",
        "Mod folder path",
        $defaultPath
    ).Trim().Trim('"')

    if ($path -and (Test-Path -LiteralPath $path)) {
        $script:SelectedModFolder = (Get-Item -LiteralPath $path -Force).FullName
        $ModFolderStatus.Text = $script:SelectedModFolder
        Set-Status "Mod folder selected." "ok"
        return $true
    }
    if ($Optional) { return $false }
    Set-Status "No valid mod folder path pasted." "err"
    return $false
}

# UI
$script:LaunchedPids = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
function Register-Proc { param($p) if ($p -and $p.Id) { [void]$LaunchedPids.Add([int]$p.Id) } }

# Modules
$script:WorkerLib = $null
function Start-Background {
    param([scriptblock]$Work, [object]$Data = $null)
    $ps = [PowerShell]::Create()
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = "STA"; $rs.Open()
    $ps.Runspace = $rs
    $ssp = $rs.SessionStateProxy
    $ssp.SetVariable("window", $window)
    $ssp.SetVariable("StatusLine", $StatusLine)
    $ssp.SetVariable("StatusDot", $StatusDot)
    $ssp.SetVariable("installDir", $installDir)
    $ssp.SetVariable("RegSearchRoots", $RegSearchRoots)
    $ssp.SetVariable("WebhookUrls", $WebhookUrls)
    $ssp.SetVariable("RelayKey", $RelayKey)
    $ssp.SetVariable("ReportingState", $script:ReportingState)
    $ssp.SetVariable("LaunchedPids", $script:LaunchedPids)
    $ssp.SetVariable("Data", $Data)
    $ssp.SetVariable("SelectedModFolder", $script:SelectedModFolder)
    # UI
    $ssp.SetVariable("Findings", $script:Findings)
    $ssp.SetVariable("SeverityWeight", $SeverityWeight)
    $ssp.SetVariable("SeverityColor", $SeverityColor)
    $ssp.SetVariable("SeverityRank", $SeverityRank)
    $ssp.SetVariable("ReportDir", $ReportDir)
    $ssp.SetVariable("FindingsPanel", $FindingsPanel)
    $ssp.SetVariable("ResultsCard", $ResultsCard)
    $ssp.SetVariable("VerdictChip", $VerdictChip)
    $ssp.SetVariable("VerdictText", $VerdictText)
    $ssp.SetVariable("VerdictDetail", $VerdictDetail)
    $ssp.SetVariable("ScoreText", $ScoreText)
    $ssp.SetVariable("AutoProgress", $AutoProgress)
    $ssp.SetVariable("ReportBtn", $ReportBtn)
    $ssp.SetVariable("FullBtn", $FullBtn)
    $ssp.SetVariable("ScanModules", $ScanModules)
    $ssp.SetVariable("SigCache", $SigCache)
    $ssp.SetVariable("KnownGoodModuleHints", $KnownGoodModuleHints)
    $ssp.SetVariable("CheatSignatures", $CheatSignatures)
    $ssp.SetVariable("CheatGenericModuleStrings", $CheatGenericModuleStrings)
    $ssp.SetVariable("CheatSignatureBlacklist", $CheatSignatureBlacklist)
    $ssp.SetVariable("SuspectPaths", $SuspectPaths)
    $ssp.SetVariable("MacroSoftware", $MacroSoftware)
    $ssp.SetVariable("RemoteControlSoftware", $RemoteControlSoftware)
    $ssp.SetVariable("VulnerableDrivers", $VulnerableDrivers)
    [void]$ps.AddScript($script:WorkerLib + "`n" + $Work.ToString())
    [void]$ps.BeginInvoke()
}

function Start-AppOrScript {
    param([Parameter(Mandatory=$true)][string]$Path, [string]$WorkingDirectory)
    if (-not $WorkingDirectory) { $WorkingDirectory = Split-Path -Parent $Path }
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $q = '"' + $Path + '"'
    switch ($ext) {
        ".cmd" { Register-Proc (Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $q -WorkingDirectory $WorkingDirectory -WindowStyle Normal -PassThru) }
        ".bat" { Register-Proc (Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $q -WorkingDirectory $WorkingDirectory -WindowStyle Normal -PassThru) }
        default { Register-Proc (Start-Process -FilePath $Path -WorkingDirectory $WorkingDirectory -WindowStyle Normal -PassThru) }
    }
}

function Start-CmdToolCommand {
    param([Parameter(Mandatory=$true)][string]$Command)
    $tempScript = [System.IO.Path]::Combine($env:TEMP, "revs_$([guid]::NewGuid().ToString('N')).ps1")
    Set-Content -LiteralPath $tempScript -Value $Command -Encoding UTF8 -Force
    $startArgs = '/c start "REVS SS TOOL" powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' + $tempScript + '"'
    Register-Proc (Start-Process -FilePath "cmd.exe" -ArgumentList $startArgs -WindowStyle Hidden -PassThru)
}

function Save-UrlToFile {
    param([Parameter(Mandatory=$true)][string]$Uri, [Parameter(Mandatory=$true)][string]$OutFile)
    $tmp = "$OutFile.download"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $client = New-Object System.Net.WebClient
    $client.Headers.Add("User-Agent", "RevsSSTool")
    try {
        $client.DownloadFile($Uri, $tmp)
        if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction Stop }
        Move-Item -LiteralPath $tmp -Destination $OutFile -Force -ErrorAction Stop
    } finally {
        $client.Dispose()
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Start-DownloadedTool {
    param([Parameter(Mandatory=$true)][string]$Directory, [string]$PreferredFile)
    if ($PreferredFile -and (Test-Path -LiteralPath $PreferredFile) -and ($PreferredFile -notmatch "\.zip$")) {
        Write-Log "Opening $(Split-Path -Leaf $PreferredFile)"
        Start-AppOrScript -Path $PreferredFile -WorkingDirectory (Split-Path -Parent $PreferredFile); return $true
    }
    $launchable = Get-ChildItem -Path $Directory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match "^\.(exe|cmd|bat)$" } |
        Sort-Object @{ Expression = { if ($_.Extension -eq ".exe") { 0 } else { 1 } } }, FullName | Select-Object -First 1
    if ($launchable) {
        Write-Log "Opening $($launchable.Name)"
        Start-AppOrScript -Path $launchable.FullName -WorkingDirectory $launchable.DirectoryName; return $true
    }
    Write-Log "Nothing to open automatically - opening the folder instead."
    Start-Process -FilePath explorer.exe -ArgumentList "`"$Directory`""; return $false
}

function Get-GitHubAssetUrl {
    param([string]$ReleaseUrl)
    if ($ReleaseUrl -match "github\.com/([^/]+)/([^/]+)/releases/latest") {
        $user = $Matches[1]; $repo = $Matches[2]
        try {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$user/$repo/releases/latest" -Headers @{"User-Agent"="RevsSSTool"} -ErrorAction Stop
            $asset = $rel.assets | Where-Object { $_.name -match "\.(exe|zip|cmd|bat)$" } | Select-Object -First 1
            if ($asset) { return @{ url=$asset.browser_download_url; name=$asset.name } }
        } catch { Write-Log "GitHub lookup failed: $($_.Exception.Message)" }
    }
    return $null
}

function Invoke-ToolDownloadAndRun {
    param($tool)
    $name = $tool.Name; $cat = $tool.Group
    Write-Log "Looking up $name..."
    $asset = Get-GitHubAssetUrl -ReleaseUrl $tool.URL
    if (-not $asset) {
        Write-Log "Couldn't grab $name automatically - opening its page in your browser."
        Set-Status "Opened $name in your browser." "ok"; Start-Process $tool.URL; return
    }
    $destDir = "$installDir\$cat\$name"
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    $destFile = "$destDir\$($asset.name)"
    if (Test-Path $destFile) { Write-Log "Already downloaded $($asset.name) - reusing it." }
    else {
        Write-Log "Downloading $($asset.name)..."
        try { Save-UrlToFile -Uri $asset.url -OutFile $destFile; Write-Log "Done downloading $($asset.name)." }
        catch { Write-Log "Download failed: $_"; Set-Status "Couldn't download $name." "err"; Start-Process $tool.URL; return }
    }
    if ($asset.name -match "\.zip$") {
        Write-Log "Unzipping $($asset.name)..."
        try { Expand-Archive -Path $destFile -DestinationPath $destDir -Force -ErrorAction Stop }
        catch { Write-Log "Unzip failed: $($_.Exception.Message)"; Set-Status "Couldn't unzip $name." "err"; Start-Process explorer.exe "`"$destDir`""; return }
        [void](Start-DownloadedTool -Directory $destDir)
    } else { [void](Start-DownloadedTool -Directory $destDir -PreferredFile $destFile) }
    Set-Status "$name is open." "ok"
}

function Invoke-WebToolDownload {
    param($tool)
    $name = $tool.Name; $url = $tool.URL
    if ($url -match "\.(zip|exe|cmd|bat)$") {
        $fileName = ($url -split "/")[-1]
        $destDir = "$installDir\$($tool.Group)\$name"
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        $destFile = "$destDir\$fileName"
        if (Test-Path $destFile) { Write-Log "Already downloaded $fileName - reusing it." }
        else {
            Write-Log "Downloading $fileName..."
            try { Save-UrlToFile -Uri $url -OutFile $destFile; Write-Log "Done downloading $fileName." }
            catch { Write-Log "Download failed: $_"; Set-Status "Couldn't download $name." "err"; Start-Process $url; return }
        }
        if ($fileName -match "\.zip$") {
            try { Expand-Archive -Path $destFile -DestinationPath $destDir -Force -ErrorAction Stop }
            catch { Write-Log "Unzip failed: $($_.Exception.Message)"; Set-Status "Couldn't unzip $name." "err"; Start-Process explorer.exe "`"$destDir`""; return }
            [void](Start-DownloadedTool -Directory $destDir)
        } else { [void](Start-DownloadedTool -Directory $destDir -PreferredFile $destFile) }
        Set-Status "$name is open." "ok"
    } else {
        Write-Log "Opening $name in your browser."; Set-Status "Opened $name in your browser." "ok"; Start-Process $url
    }
}

# Reports
function Report-Run {
    param([string]$Action, [string]$Detail)
    if (-not $WebhookUrls) { return }
    if (-not $ReportingState -or -not $ReportingState.Enabled) { return }
    $act = if ($Action.Length -gt 1024) { $Action.Substring(0,1024) } else { $Action }
    $fields = @(
        @{ name="Action"; value=$act; inline=$false }
    )
    if ($Detail) {
        $d = if ($Detail.Length -gt 1000) { $Detail.Substring(0,1000) } else { $Detail }
        $fields += @{ name="Output"; value=('```' + "`n" + $d + "`n" + '```'); inline=$false }
    }
    $embed = @{ title=[char]0x25B6 + " Action Run"; color=16751406; fields=$fields; timestamp=(Get-Date -Format "yyyy-MM-ddTHH:mm:ss") + ".000Z" }
    $payload = @{ embeds = @($embed) } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    foreach ($url in $WebhookUrls) {
        if (-not $ReportingState.Enabled) { break }
        try {
            $req = [Net.HttpWebRequest]::Create($url)
            $req.Method = "POST"; $req.ContentType = "application/json"; $req.UserAgent = "Mozilla/5.0"; $req.Timeout = 10000
            if ($RelayKey) { $req.Headers.Add("X-Revs-Key", $RelayKey) }
            $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
            $req.GetResponse().Close()
        } catch {}
    }
}

# Cheats
# Confidence

$CheatClientFullwidthRegex = '[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]{2,}'
$CheatClientJapaneseClassRegex = '[\u3040-\u309F\u30A0-\u30FF]'

$CheatClientSignatures = @(

    @{
        Name       = 'JVM Injection (generic javaagent/bootclasspath/JDWP)'
        Kind       = 'jar'
        Strings    = @('-javaagent:', '-Xbootclasspath/p:', '-Xbootclasspath/a:', '-agentlib:jdwp', '-agentpath:', 'JDWP.VirtualMachine.AllModules')
        Paths      = @()
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Weave Loader (universal injection loader)'
        Kind       = 'jar'
        Strings    = @('weave-loader', 'Weave-Loader', 'net/weavemc', 'weavemc')
        Paths      = @('%USERPROFILE%\.weave', '%USERPROFILE%\.weave\mods\*.jar', '%USERPROFILE%\.weave\loader.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Cheat JAR Obfuscator (Skidfuscator/Paramorphism/Radon/Caesium/Bozar/Branchlock/Binscure/Qprotect/Zelix/Stringer/JNIC/Scuti/Smoke)'
        Kind       = 'jar'
        Strings    = @('dev/skidfuscator', 'skidfuscator.dev', 'Paramorphism', 'paramorphism-', 'dev/paramorphism',
                       'ItzSomebody/Radon', 'me/itzsomebody/radon', 'Radon Obfuscator',
                       'sim0n/Caesium', 'Caesium Obfuscator', 'dev/sim0n/caesium',
                       'vimasig/Bozar', 'Bozar Obfuscator', 'com/bozar',
                       'branchlock.dev', 'com/binscure', 'superblaubeere27',
                       'mdma.dev/qprotect', 'ZelixKlassMaster', 'ZKMFLOW', 'com/zelix',
                       'StringerJavaObfuscator', 'com/licel/stringer',
                       'jnic-obfuscator', 'jnic.obf', 'ScutiObf', 'scuti.obf', 'SmokeObf', 'smoke.obf')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @()
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Cheat Mixin Refmap / Accessor artifacts'
        Kind       = 'jar'
        Strings    = @('phantom-refmap.json', 'client-refmap.json', 'cheat-refmap.json',
                       'LicenseCheckMixin', 'ClientPlayerInteractionManagerAccessor', 'ClientPlayerEntityMixim',
                       'obfuscatedAuth', 'AuthBypass')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @()
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Cheat GUI / native hook libraries in JAR'
        Kind       = 'jar'
        Strings    = @('imgui.binding', 'imgui.gl3', 'imgui.glfw', 'GlobalScreen', 'NativeKeyListener', 'jnativehook', 'JNativeHook')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },

    @{
        Name       = 'Doomsday Client'
        Kind       = 'jar'
        Strings    = @(
            'doomsdayclient', 'DoomsdayClient', 'doomsday.jar', 'doomsdayclient.com', 'Doomsday Client',
            'Premain-Class: net.java.ag', 'Main-Class: net.java.m', 'Can-Retransform-Classes: true',
            '"id":"dd"', 'modId="dd"', 'displayName="dd"', 'net/java/ag.class', 'net/java/m.class',
            'mod_d.class', 'addon3.json', 'addon4.json',
            'SelfDestruct', 'ClickAimAssist', 'CystalOptimizer', 'MoveClipBypass', 'NoSlownDown',
            'SaverBreakBlock', 'ClientSpoofer', 'GhostHand', 'LegitCrosshair', 'MiddleClickFriend',
            'PacketBreak', 'WorldTime', 'XCarry'
        )
        Markers    = @(
            'DoomsDay loader structure',
            'DoomsDay javaagent manifest',
            'DoomsDay dd mod metadata',
            'DoomsDay addon metadata'
        )
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%USERPROFILE%\Downloads\*.jar', '%TEMP%\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
        MemoryMinMarkers = 4
    },
    @{
        Name       = 'Prestige Client'
        Kind       = 'jar'
        Strings    = @('PrestigeClient', 'prestige client', 'prestigeclient.vip', 'prestigeclient.org', 'prestige-client.live', 'zPrestige')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%USERPROFILE%\Downloads\*.exe')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Vape V4 (native injector)'
        Kind       = 'exe'
        Strings    = @('vape.gg', 'VapeClient', 'vapeclient', 'Manthe Industries', 'SilentAura', 'HitFlick', 'HitSelect', 'ThrowDebuff', 'InvCleaner', 'BedPlates', 'MurdererFinder', 'AntiFireball', 'KnockbackDelay', 'MouseDelayFix', 'Blockhit-Animation', 'Reach-Display', 'Inventory-Blur', 'Hit-Color', 'AutoHotbar', 'InventoryFill', 'ArmorSwitch', 'TargetFilter', 'SpawnerFinder', 'Party-Overlay', 'Rearview', 'Text-GUI', 'Duel-Info')
        Paths      = @('%USERPROFILE%\.vape', '%APPDATA%\.vape', '%USERPROFILE%\Downloads\*.exe')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Vape Lite (javaagent dropper)'
        Kind       = 'jar'
        Strings    = @('VapeLite', 'vape.gg', '144.217.241.181')
        Paths      = @('%TEMP%\*.jar', '%USERPROFILE%\.vape')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Vape legacy 2.x (carved binary literals)'
        Kind       = 'jar'
        Strings    = @('com/sun/jna/z/Main', 'yCcADi', '74.91.125.194', '142.44.246.31')
        Paths      = @()
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Novoware Client'
        Kind       = 'jar'
        Strings    = @('novoware', 'Novoware Client', 'novoclient', 'novoware.eu', 'novoware.shop')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%TEMP%\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'LiquidBounce'
        Kind       = 'jar'
        Strings    = @('net/ccbluex', 'net.ccbluex', 'liquidbounce.mixins.json', 'liquidbounce.accesswidener', 'liquidbounce.net', 'forums.ccbluex.net', 'fdp-client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Meteor Client'
        Kind       = 'jar'
        Strings    = @('meteordevelopment.meteorclient', 'meteor-client.mixins.json', 'meteor-client.classtweaker', 'assets/meteor-client/icon.png', 'meteor-client:build_number', 'meteorclient.com')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%APPDATA%\.minecraft\meteor-client')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Wurst Client'
        Kind       = 'jar'
        Strings    = @('net.wurstclient', 'net/wurstclient', 'net/wurstclient/hacks', 'WurstInitializer', 'wurst.mixins.json', 'wurst.accesswidener', 'wurstclient.net', 'wurstclient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%APPDATA%\.minecraft\wurst')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Aristois'
        Kind       = 'jar'
        Strings    = @('https://maven.aristois.net/manifest', 'maven.aristois.net', 'aristois')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Nova Client'
        Kind       = 'jar'
        Strings    = @('api.novaclient.lol', 'aHR0cDovL2FwaS5ub3ZhY2xpZW50LmxvbC93ZWJob29rLnR4dA==', 'novaclient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Chainlibs private crystal client'
        Kind       = 'jar'
        Strings    = @('org.chainlibs.module.impl.modules', 'org/chainlibs/module/impl/modules', 'org.chainlibs')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Dqrkis Client'
        Kind       = 'jar'
        Strings    = @('Dqrkis Client', 'dqrkis.xyz', 'dqrkis', 'lvstrng')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Krypton Client (cheat, NOT the legit Krypton optimization mod)'
        Kind       = 'jar'
        Strings    = @('dev.krypton', 'dev/krypton', 'skid.krypton', 'skid/krypton')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Novoline'
        Kind       = 'jar'
        Strings    = @('cc/novoline', 'cc.novoline', 'novoline')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Moonlight Client'
        Kind       = 'jar'
        Strings    = @('wtf/moonlight', 'wtf.moonlight', 'moonlight client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'KAMI Blue'
        Kind       = 'jar'
        Strings    = @('me/zeroeightsix/kami', 'me.zeroeightsix.kami', 'kamiblue', 'kami client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%APPDATA%\.minecraft\kamiblue')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'CheatBreaker'
        Kind       = 'jar'
        Strings    = @('com/cheatbreaker', 'com.cheatbreaker')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Greaj Client'
        Kind       = 'jar'
        Strings    = @('xyz/greaj', 'xyz.greaj')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Gamble Client'
        Kind       = 'jar'
        Strings    = @('dev.gambleclient', 'dev/gambleclient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Virel / Orchard'
        Kind       = 'jar'
        Strings    = @('dev.virel', 'dev/virel')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Alan Clients'
        Kind       = 'jar'
        Strings    = @('com/alan/clients', 'com.alan.clients')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Maxstats Client'
        Kind       = 'jar'
        Strings    = @('club/maxstats', 'club.maxstats')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'OpAI Client'
        Kind       = 'jar'
        Strings    = @('today/opai', 'today.opai')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Generic net/minecraft/injection package'
        Kind       = 'jar'
        Strings    = @('net/minecraft/injection', 'net.minecraft.injection')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Walksy Crystal Optimizer / Replace Mod'
        Kind       = 'jar'
        Strings    = @('WalksyCrystalOptimizerMod', 'WalksyOptimizer', 'WalskyOptimizer', 'walsky.optimizer', 'walksy_optimizer', 'LWFH Crystal')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Legacy injection clients (AVIX/Bape/Drek/Gucci/Harambe/Incognito/Kurium/Onetap/Spooky/Zuiy/Vea/TimeChanger)'
        Kind       = 'jar'
        Strings    = @('/AVIX-Config', 'trumpclientftw_bape', 'dg82fo.pw', 'G0ttaDipMen.java', 'Harambe.png', 'czaarek99',
                       'cracked by dinkio', 'onetap.cc', 'bspkrs.IlIIIlIlIllIIlllIllIllIII', '0SO1Lk2KASxzsd',
                       '/tcpnodelaymod/COM1', '/a.class:::0', 'TCNH$1', '+(M0G.V')
        Paths      = @()
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Orbdiff JARParser Flag C (client identity constants)'
        Kind       = 'jar'
        Strings    = @('/5OFV7PFTIMB0V', '/net/java/a', '/net/java/b', '/net/java/c', '/net/java/d', '/net/java/e',
                       '-1083759330220665782', '-4062297973245990737')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'high'
    },
    @{
        Name       = 'Java Autoclicker (internal)'
        Kind       = 'jar'
        Strings    = @('Autoclicker.class', 'me.tojatta.clicker.ui.cl', 'keystrokesmod', 'autoclicker', 'autoclick')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar', '%TEMP%\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },

    @{
        Name       = 'Rise Client'
        Kind       = 'jar'
        Strings    = @('rise.today', 'riseclient.com', 'rise client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Intent Client'
        Kind       = 'jar'
        Strings    = @('IntentClient', 'intent.store', 'intent client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Sigma Client'
        Kind       = 'jar'
        Strings    = @('Sigma Client', 'sigma client', 'sigmaclient.net', 'sigmaclient.cloud', 'HyperAura', 'PrecisionCrit', 'VelocityForge', 'TotemGuard', 'ComboExtender', 'AimEngine', 'SwordSwap')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Impact Client'
        Kind       = 'jar'
        Strings    = @('impactclient', 'impact client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'RusherHack'
        Kind       = 'jar'
        Strings    = @('rusherhack', 'org.rusherhack')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Astolfo Client'
        Kind       = 'jar'
        Strings    = @('AstolfoClient', 'astolfo client', 'astolfo')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Konas Client'
        Kind       = 'jar'
        Strings    = @('konas client', 'KonasClient', 'konas')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Pandaware'
        Kind       = 'jar'
        Strings    = @('pandaware')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Asteria Client'
        Kind       = 'jar'
        Strings    = @('AsteriaClient', 'asteria client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Argon Client'
        Kind       = 'jar'
        Strings    = @('ArgonClient', 'argon client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Xenon Client'
        Kind       = 'jar'
        Strings    = @('XenonClient', 'xenon client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Catlean Client'
        Kind       = 'jar'
        Strings    = @('CatleanClient', 'catlean client', 'catlean')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Virgin Client'
        Kind       = 'jar'
        Strings    = @('VirginClient', 'virgin client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Gypsy Client'
        Kind       = 'jar'
        Strings    = @('GypsyClient', 'gypsy client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Grim Client (cheat, not GrimAC)'
        Kind       = 'jar'
        Strings    = @('GrimClient', 'grim client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Hellion Client'
        Kind       = 'jar'
        Strings    = @('HellionClient', 'hellion client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Exhibition Client'
        Kind       = 'jar'
        Strings    = @('exhibition client', 'ExhibitionClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Future Client'
        Kind       = 'jar'
        Strings    = @('futureClient', 'future client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Inertia Client'
        Kind       = 'jar'
        Strings    = @('inertia client', 'InertiaClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'ForgeHax'
        Kind       = 'jar'
        Strings    = @('forgehax', 'com.matt.forgehax')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'SalHack'
        Kind       = 'jar'
        Strings    = @('salhack', 'SalHack Client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'ThunderHack'
        Kind       = 'jar'
        Strings    = @('thunderhack', 'ThunderHack Recode')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Raven B+ / B++ (Weave-based)'
        Kind       = 'jar'
        Strings    = @('Raven B++', 'Raven B+', 'RavenB', 'raven client')
        Paths      = @('%USERPROFILE%\.weave\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = '198Macros'
        Kind       = 'jar'
        Strings    = @('198Macros', 'Macro198', 'macro_198')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'medium'
    },
    @{
        Name       = 'Cheat Engine / speedhack layer'
        Kind       = 'exe'
        Strings    = @('cheatengine.exe', 'cheatengine681.exe', 'speedhack.dll', 'speedhack-x86_64.dll', 'speedhack-i386.dll', 'monoscript.lua')
        Paths      = @('%TEMP%\*.exe', '%USERPROFILE%\Downloads\*.exe')
        Processes  = @('cheatengine-x86_64.exe', 'cheatengine-i386.exe', 'Cheat Engine.exe')
        Registry   = @()
        Confidence = 'medium'
    },

    @{
        Name       = 'Entropy Client'
        Kind       = 'exe'
        Strings    = @('entropy.club', 'Entropy Software')
        Paths      = @()
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Slinky Client'
        Kind       = 'exe'
        Strings    = @('slinky.gg', 'Slinky')
        Paths      = @('%APPDATA%\slinky', '%APPDATA%\.slinky', '%LOCALAPPDATA%\slinky', '%USERPROFILE%\.slinky')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Onyx Client'
        Kind       = 'jar'
        Strings    = @('Onyx Client', 'onyx client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Pandora Client'
        Kind       = 'jar'
        Strings    = @('pandora client', 'PandoraClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Ares Client'
        Kind       = 'jar'
        Strings    = @('ares client', 'AresClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Sapphire Client / Sapphire Lite'
        Kind       = 'jar'
        Strings    = @('Sapphire Lite', 'sapphire client')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Skid-family clients (SkidBounce/Skidcraft/SalHackSkid)'
        Kind       = 'jar'
        Strings    = @('SkidBounce', 'Skidcraft', 'SalHackSkid')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Nodus Client'
        Kind       = 'jar'
        Strings    = @('nodus client', 'NodusClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Zeroday Client'
        Kind       = 'jar'
        Strings    = @('zeroday client', 'ZerodayClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Zamorak Client'
        Kind       = 'jar'
        Strings    = @('zamorak client', 'ZamorakClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Augustus Client'
        Kind       = 'jar'
        Strings    = @('augustus client', 'AugustusClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Akrien Client'
        Kind       = 'jar'
        Strings    = @('akrien client', 'AkrienClient', 'akrien')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    },
    @{
        Name       = 'Nightware Client'
        Kind       = 'jar'
        Strings    = @('nightware client', 'NightwareClient')
        Paths      = @('%APPDATA%\.minecraft\mods\*.jar')
        Processes  = @('javaw.exe', 'java.exe')
        Registry   = @()
        Confidence = 'low'
    }
)

# Live
# Reports
$CheatGenericModuleStrings = @(
    'AutoCrystal','AutoHitCrystal','AutoAnchor','DoubleAnchor','SafeAnchor','AirAnchor','AnchorTweaks','AnchorAction',
    'CrystalAura','AnchorAura','AnchorFill','AnchorPlace','LWFH Crystal',
    'dontPlaceCrystal','dontBreakCrystal','canPlaceCrystalServer','autoCrystalPlaceClock','placeInterval','breakInterval',
    'stopOnKill','activateOnRightClick','holdCrystal','damagetick','fakePunch','healPotSlot','speedPotSlot','strengthPotSlot',
    'AutoTotem','InventoryTotem','HoverTotem','LegitTotem','OffhandTotem','TotemSwitch','REOFFHAND_TOTEM','PopSwitch',
    'KillAura','ClickAura','MultiAura','ForceField','LegitAura','AimBot','AutoAim','SilentAim','AimLock','HeadSnap',
    'AimAssist','TriggerBot','BowAimbot','BowSpam','AutoBow','AutoCrit','CritBypass','AlwaysCrit',
    'ShieldDisabler','ShieldBreaker','AxeSpam','MaceSwap','AutoMace','SpearSwap','StunSlam','WTap','JumpReset','SprintReset',
    'AntiMissClick','ReachHack','ExtendReach','LongReach','HitboxExpand','LagReach',
    'AntiKB','NoKnockback','Antiknockback','GrimVelocity','GrimDisabler','VelocitySpoof','KBReduce',
    'FlyHack','CreativeFlight','BoatFly','PacketFly','AirJump','SpeedHack','BHop','BunnyHop',
    'AntiFall','NoFallDamage','SafeFall','StepHack','FastClimb','AutoStep','HighStep',
    'WaterWalk','LiquidWalk','LavaWalk','NoSlow','NoSlowdown','NoWeb','NoSoulSand',
    'ElytraSwap','ElytraSpeed','InstantElytra','NoJumpDelay',
    'ScaffoldWalk','FastBridge','BuildHelper','AutoBridge','Nuker','NukerLegit','InstantBreak',
    'GhostHand','NoSwing','PlaceAssist','AirPlace','AutoPlace','InstantPlace','FastPlace','AutoBreach','PacketMine',
    'PlayerESP','MobESP','ItemESP','StorageESP','ChestESP','BlockESP','Tracers','NameTagsHack',
    'XRayHack','OreFinder','CaveFinder','OreESP','NewChunks','ChunkBorders','TunnelFinder','WallHack',
    'FreezePlayer','FakeItem','Fakenick',
    'AutoClicker','DoubleClicker','JitterClick','ButterflyClick','CPSBoost',
    'AutoPot','AutoPotRefill','AutoEat','AutoMine','AutoArmor','AutoDoubleHand','AutoFirework','AutoWeb','AntiWeb',
    'AutoGap','AutoPearl','KeyPearl','AutoTPA','ChestStealer','ChestSteal','InvManager','InvMovebypass',
    'FastXP','FastExp','WebMacro','LootYeeter','BaseFinder','StashFinder','TrailFinder',
    'FakeLag','PingSpoof','FakeInv','PackSpoof','FakeLatency','FakePing','SpoofRotation','PositionSpoof',
    'GameSpeed','SpeedTimer','SelfDestruct','HideClient','AuthBypass','obfuscatedAuth',
    'GrimBypass','VulcanBypass','MatrixBypass','AACBypass','VerusDisabler','IntaveBypass','WatchdogBypass',
    'PacketWalk','PacketSneak','PacketCancel','PacketDupe','PacketSpam',
    'SessionStealer','TokenLogger','TokenGrabber','DiscordToken','RemoteAccess','ReverseShell','C2Server','Backdoor','KeyLogger',
    'setBlockBreakingCooldown','getBlockBreakingCooldown','blockBreakingCooldown','onBlockBreaking','setItemUseCooldown',
    'invokeDoAttack','invokeDoItemUse','invokeOnMouseButton','onPushOutOfBlocks','onIsGlowing',
    'findKnockbackSword','attackRegisteredThisClick','preventSwordBlockBreaking','preventSwordBlockAttack','swapBackToOriginalSlot',
    'DOUBLE_ESCAPE','DOUBLE_RIGHTCLICK_FIRST','DOUBLE_RIGHTCLICK_SECOND','POST_CYCLE_DELAY','PLACE_OBI','WAIT_OBI',
    'PLACE_CRYSTAL','BREAK_CRYSTAL','ROTATING_DOWN','ROTATING_BACK','BONEMEALING','POT_CHEATS',
    'mace_swap','quick_strike','macro_198','stun_slam','safe_anchor','double_anchor','auto_pot_refill',
    'walksy_optimizer','key_pearl','aim_assist','auto_neth_pot','auto_dtap','trigger_bot','auto_web',
    'Breaking shield with axe...','Failed to switch to mace after axe!',
    'Automatically switches to sword when hitting with totem','Places two anchors for massive damage'
)

# Cheats
$CheatSignatureBlacklist = @(
    'krypton','Ryzen','Argon','Xenon','Pandora','baritone','com/moonsworth','getPlayerPOVHitResult',
    'clicker','fly','xray','cheat','hack','client','inject','bypass','Reach','Velocity','Sprint',
    'Donut','Freecam','Blatant','Search','Panic','Refill','orchard','skilled','azura','inertia','gypsy',
    'Hellion','exhibition','Prestige','Asteria','nG@W','hi.a2','Sa_Vc','5d@56','104.22.37.186','autohotkey','.ahk'
)
# Live
$CheatSignatures = $CheatClientSignatures

# Drivers
# Cheats
$VulnerableDrivers = @(
    'gdrv.sys','gdrv2.sys','gdrv3.sys','rtcore32.sys','rtcore64.sys','winio.sys','winio64.sys',
    'winring0.sys','winring0x64.sys','inpout32.sys','inpoutx64.sys','ene.sys','eneio.sys','eneio64.sys',
    'cpuz.sys','cpuz136_x64.sys','cpuz141_x64.sys','cpuz149_x64.sys','asrdrv101.sys','asrdrv102.sys',
    'asrdrv103.sys','asrdrv104.sys','asrdrv106.sys','asrdrv107.sys','capcom.sys','iqvw64e.sys','iqvw32.sys',
    'nal.sys','dbk32.sys','dbk64.sys','kprocesshacker.sys','kph.sys','kph2.sys','kph3.sys','procxp152.sys',
    'procexp152.sys','phymem.sys','phymem64.sys','rwdrv.sys','lirsgt.sys','msio64.sys','glckio2.sys'
)

# UI
# Input
$MacroSoftware = @(
    @{
        Name='AutoHotkey'; Severity='Medium'; Processes=@('AutoHotkey.exe','AutoHotkey64.exe','AutoHotkeyU64.exe','AutoHotkeyU32.exe')
        Paths=@('%ProgramFiles%\AutoHotkey','%ProgramFiles(x86)%\AutoHotkey','%USERPROFILE%\Documents\AutoHotkey','%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\*.ahk')
        Registry=@('HKCU:\Software\AutoHotkey','HKLM:\Software\AutoHotkey')
        Note='AutoHotkey is a general scripting engine often used for autoclickers. Inspect scripts and startup entries before judging.'
    },
    @{
        Name='X-Mouse Button Control'; Severity='Medium'; Processes=@('XMouseButtonControl.exe','XMouseButtonSvc.exe')
        Paths=@('%APPDATA%\Highresolution Enterprises\XMouseButtonControl','%ProgramFiles%\Highresolution Enterprises\X-Mouse Button Control','%ProgramFiles(x86)%\Highresolution Enterprises\X-Mouse Button Control')
        Registry=@('HKCU:\Software\Highresolution Enterprises\XMouseButtonControl')
        Note='XMBC can remap mouse buttons and build click sequences. Review profiles for repeated left/right click actions.'
    },
    @{
        Name='Logitech G HUB / LGS'; Severity='Low'; Processes=@('lghub.exe','lghub_agent.exe','lghub_updater.exe','LCore.exe')
        Paths=@('%LOCALAPPDATA%\LGHUB','%APPDATA%\LGHUB','%LOCALAPPDATA%\Logitech\Logitech Gaming Software','%APPDATA%\Logitech\Logitech Gaming Software')
        Registry=@('HKCU:\Software\Logitech')
        Note='Logitech profiles can contain mouse macros. Open the profile database or app and check click bindings.'
    },
    @{
        Name='Razer Synapse'; Severity='Low'; Processes=@('Razer Synapse 3.exe','Razer Synapse Service.exe','RazerCentralService.exe','RzSynapse.exe')
        Paths=@('%PROGRAMDATA%\Razer\Synapse3','%LOCALAPPDATA%\Razer\Synapse3','%LOCALAPPDATA%\Razer','%PROGRAMFILES(x86)%\Razer')
        Registry=@('HKCU:\Software\Razer','HKLM:\Software\Razer')
        Note='Razer profiles may store macros locally or in cloud-synced data. Check profiles, logs and assigned buttons.'
    },
    @{
        Name='Corsair iCUE'; Severity='Low'; Processes=@('iCUE.exe','Corsair.Service.exe','Corsair.Service.DisplayAdapter.exe')
        Paths=@('%APPDATA%\Corsair\CUE','%LOCALAPPDATA%\Corsair','%PROGRAMDATA%\Corsair')
        Registry=@('HKCU:\Software\Corsair','HKLM:\Software\Corsair')
        Note='iCUE can assign repeated actions to mouse buttons. Inspect hardware and software profiles.'
    },
    @{
        Name='ROCCAT Swarm'; Severity='Low'; Processes=@('ROCCAT_Swarm.exe','ROCCAT_Swarm_Monitor.exe')
        Paths=@('%APPDATA%\ROCCAT\SWARM','%APPDATA%\ROCCAT\SWARM\macro','%APPDATA%\ROCCAT\SWARM\custom_macro_list.*','%APPDATA%\ROCCAT\SWARM\macro_list.dat')
        Registry=@('HKCU:\Software\ROCCAT')
        Note='Swarm stores macro lists on disk. Review custom macro files and recent modifications.'
    },
    @{
        Name='SteelSeries GG / Engine'; Severity='Low'; Processes=@('SteelSeriesGG.exe','SteelSeriesEngine.exe','SteelSeriesEngine3.exe')
        Paths=@('%PROGRAMDATA%\SteelSeries\GG','%APPDATA%\SteelSeries\GG','%PROGRAMDATA%\SteelSeries\SteelSeries Engine 3')
        Registry=@('HKCU:\Software\SteelSeries','HKLM:\Software\SteelSeries')
        Note='SteelSeries profiles can bind repeat actions. Check Engine/GG configs and profile assignments.'
    },
    @{
        Name='Bloody / Glorious / generic mouse tools'; Severity='Low'; Processes=@('Bloody7.exe','Bloody6.exe','Glorious Core.exe','GloriousCore.exe','Model O Software.exe')
        Paths=@('%PROGRAMFILES(x86)%\Bloody7','%PROGRAMFILES%\Glorious Core','%LOCALAPPDATA%\Glorious Core','%APPDATA%\Glorious Core')
        Registry=@('HKCU:\Software\Bloody','HKCU:\Software\Glorious')
        Note='Mouse vendor tools can store debounce and macro settings. Check profiles for click automation.'
    }
)

# Input
$RemoteControlSoftware = @(
    @{
        Name='AnyDesk'; Severity='Low'; RunningSeverity='Low'; Processes=@('AnyDesk.exe'); Services=@('AnyDesk')
        Paths=@('%PROGRAMFILES(x86)%\AnyDesk','%PROGRAMFILES%\AnyDesk','%APPDATA%\AnyDesk')
        Note='Often expected during screenshares; note it, then confirm the checked machine is the one running Minecraft.'
    },
    @{
        Name='TeamViewer'; Severity='Low'; RunningSeverity='Low'; Processes=@('TeamViewer.exe','TeamViewer_Service.exe'); Services=@('TeamViewer')
        Paths=@('%PROGRAMFILES%\TeamViewer','%PROGRAMFILES(x86)%\TeamViewer','%APPDATA%\TeamViewer')
        Note='Common support software; verify whether it is only the screenshare channel or controlling input from elsewhere.'
    },
    @{
        Name='RustDesk'; Severity='Low'; RunningSeverity='Medium'; Processes=@('rustdesk.exe'); Services=@('RustDesk')
        Paths=@('%PROGRAMFILES%\RustDesk','%APPDATA%\RustDesk','%LOCALAPPDATA%\RustDesk')
        Note='Can give another machine remote input. Check connection history if it is active.'
    },
    @{
        Name='Parsec / Moonlight / Sunshine'; Severity='Low'; RunningSeverity='Medium'; Processes=@('parsecd.exe','parsec.exe','Moonlight.exe','sunshine.exe')
        Services=@('SunshineService')
        Paths=@('%APPDATA%\Parsec','%LOCALAPPDATA%\Parsec','%PROGRAMFILES%\Parsec','%APPDATA%\Moonlight Game Streaming Project','%PROGRAMFILES%\Sunshine')
        Note='Low-latency game streaming can hide host-vs-guest control. Confirm where the game is actually rendered.'
    },
    @{
        Name='Chrome Remote Desktop'; Severity='Low'; RunningSeverity='Medium'; Processes=@('remoting_host.exe','remote_assistance_host.exe'); Services=@('chromoting')
        Paths=@('%PROGRAMFILES(x86)%\Google\Chrome Remote Desktop','%LOCALAPPDATA%\Google\Chrome Remote Desktop')
        Note='Remote host software can accept input without an obvious window.'
    },
    @{
        Name='Barrier / Synergy / Mouse Without Borders'; Severity='Medium'; RunningSeverity='High'; Processes=@('barrier.exe','barrierc.exe','barriers.exe','synergy.exe','synergyc.exe','synergys.exe','MouseWithoutBorders.exe')
        Services=@('Barrier','Synergy','MouseWithoutBordersSvc')
        Paths=@('%PROGRAMFILES%\Barrier','%PROGRAMFILES%\Synergy','%PROGRAMFILES(x86)%\Microsoft Garage\Mouse without Borders')
        Note='Input-sharing tools let another PC control this keyboard and mouse directly.'
    }
)

# Reports

$SeverityWeight = @{ Info = 0; Low = 4; Medium = 12; High = 30; Critical = 60 }
$SeverityColor  = @{ Info = "#9A9A9A"; Low = "#60A5FA"; Medium = "#FBBF24"; High = "#FB923C"; Critical = "#F87171" }
$SeverityRank   = @{ Info = 0; Low = 1; Medium = 2; High = 3; Critical = 4 }

# Helpers
$Findings = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$ReportDir = "$env:USERPROFILE\Downloads\RevsSSTool-Reports"

function New-Finding {
    param(
        [Parameter(Mandatory=$true)][string]$Module,
        [Parameter(Mandatory=$true)][string]$Title,
        [ValidateSet("Info","Low","Medium","High","Critical")][string]$Severity = "Info",
        [string]$Detail = "",
        [string[]]$Evidence = @()
    )
    [pscustomobject]@{
        Module   = $Module
        Title    = $Title
        Severity = $Severity
        Detail   = $Detail
        Evidence = @($Evidence)
        Time     = (Get-Date)
    }
}

# UI
function Add-FindingRow {
    param($Finding)
    $f = $Finding
    $FindingsPanel.Dispatcher.Invoke([Action]{
        $color = $SeverityColor[$f.Severity]
        if (-not $color) { $color = "#9A9A9A" }

        $row = New-Object System.Windows.Controls.Border
        $row.CornerRadius = "6"
        $row.BorderThickness = "3,0,0,0"
        $row.BorderBrush = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($color)))
        $row.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString("#2B2B2B")))
        $row.Padding = "11,8"
        $row.Margin = "0,0,0,7"

        $sp = New-Object System.Windows.Controls.StackPanel

        $head = New-Object System.Windows.Controls.StackPanel
        $head.Orientation = "Horizontal"
        $sev = New-Object System.Windows.Controls.TextBlock
        $sev.Text = $f.Severity.ToUpper()
        $sev.FontSize = 9.5; $sev.FontWeight = "Bold"; $sev.Width = 58
        $sev.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($color)))
        $sev.VerticalAlignment = "Center"
        $ttl = New-Object System.Windows.Controls.TextBlock
        $ttl.Text = $f.Title; $ttl.FontSize = 12; $ttl.FontWeight = "SemiBold"; $ttl.Foreground = "#F5F5F5"
        $ttl.TextWrapping = "Wrap"; $ttl.MaxWidth = 700
        $mod = New-Object System.Windows.Controls.TextBlock
        $mod.Text = $f.Module; $mod.FontSize = 9.5; $mod.Foreground = "#9A9A9A"; $mod.Margin = "10,1,0,0"
        $mod.VerticalAlignment = "Center"
        $head.Children.Add($sev) | Out-Null
        $head.Children.Add($ttl) | Out-Null
        $head.Children.Add($mod) | Out-Null
        $sp.Children.Add($head) | Out-Null

        if ($f.Detail) {
            $d = New-Object System.Windows.Controls.TextBlock
            $d.Text = $f.Detail; $d.FontSize = 11; $d.Foreground = "#C8C8C8"
            $d.TextWrapping = "Wrap"; $d.Margin = "58,3,0,0"
            $sp.Children.Add($d) | Out-Null
        }
        if ($f.Evidence -and $f.Evidence.Count -gt 0) {
            $shown = @($f.Evidence | Select-Object -First 8)
            $text  = ($shown -join "`n")
            if ($f.Evidence.Count -gt 8) { $text += "`n... +$($f.Evidence.Count - 8) more (see report)" }
            $e = New-Object System.Windows.Controls.TextBlock
            $e.Text = $text; $e.FontFamily = "Consolas"; $e.FontSize = 10.5; $e.Foreground = "#9A9A9A"
            $e.TextWrapping = "Wrap"; $e.Margin = "58,4,0,0"
            $sp.Children.Add($e) | Out-Null
        }

        $row.Child = $sp
        $FindingsPanel.Children.Add($row) | Out-Null
        $ResultsCard.Visibility = "Visible"
    })
}

function Clear-Findings {
    $Findings.Clear()
    $FindingsPanel.Dispatcher.Invoke([Action]{
        $FindingsPanel.Children.Clear()
        $ResultsCard.Visibility = "Collapsed"
        $ReportBtn.Visibility = "Collapsed"
    })
}

# Reports
function Add-Finding {
    param($Finding)
    if (-not $Finding) { return }
    foreach ($f in @($Finding)) {
        if (-not $f) { continue }
        [void]$Findings.Add($f)
        if ($f.Severity -ne "Info") { Add-FindingRow $f }
    }
}

function Set-Progress {
    param([string]$Text)
    $AutoProgress.Dispatcher.Invoke([Action]{ $AutoProgress.Text = $Text })
}

# Score
# Launcher
# Cheats
function Get-Verdict {
    param($FindingSet)
    $score = 0
    foreach ($f in @($FindingSet)) {
        $w = $SeverityWeight[$f.Severity]
        if ($w) { $score += $w }
    }
    if ($score -gt 100) { $score = 100 }
    $band = if ($score -ge 60) { "CHEATING" }
            elseif ($score -ge 30) { "SUSPICIOUS" }
            elseif ($score -ge 10) { "INCONCLUSIVE" }
            else { "CLEAN" }
    $color = switch ($band) {
        "CHEATING"     { "#F87171" }
        "SUSPICIOUS"   { "#FB923C" }
        "INCONCLUSIVE" { "#FBBF24" }
        default        { "#34D399" }
    }
    [pscustomobject]@{ Score = $score; Band = $band; Color = $color }
}

function Show-Verdict {
    param($Verdict, [string]$Detail)
    $v = $Verdict; $d = $Detail
    $VerdictText.Dispatcher.Invoke([Action]{
        $VerdictText.Text = $v.Band
        $VerdictChip.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($v.Color)))
        $VerdictDetail.Text = $d
        $ScoreText.Text = "risk $($v.Score)/100"
        $ResultsCard.Visibility = "Visible"
    })
}

# Reports
function Get-MachineHeader {
    $lines = @()
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $up = (Get-Date) - $os.LastBootUpTime
        $lines += "Computer      : $($cs.Name)"
        $lines += "User          : $env:USERDOMAIN\$env:USERNAME"
        $lines += "OS            : $($os.Caption) $($os.Version) (build $($os.BuildNumber))"
        $lines += "Installed     : $($os.InstallDate)"
        $lines += "Last boot     : $($os.LastBootUpTime)"
        $lines += ("Uptime        : {0}d {1}h {2}m" -f $up.Days, $up.Hours, $up.Minutes)
    } catch {
        $lines += "Computer      : $env:COMPUTERNAME"
        $lines += "User          : $env:USERDOMAIN\$env:USERNAME"
        $lines += "System info   : unavailable ($($_.Exception.Message))"
    }
    try {
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $lines += "Elevated      : $admin"
    } catch {}
    $lines += "Report time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    return $lines
}

# Reports
# UI
function Write-CheckReport {
    param($FindingSet, $Verdict, [string[]]$SkippedModules)
    if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
    $path = Join-Path $ReportDir ("REVS-check-{0}-{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd-HHmmss"))

    $out = New-Object System.Text.StringBuilder
    [void]$out.AppendLine("REVS SS TOOL - automated PC check report")
    [void]$out.AppendLine(("=" * 72))
    foreach ($l in (Get-MachineHeader)) { [void]$out.AppendLine($l) }
    [void]$out.AppendLine("Verdict       : $($Verdict.Band)  (risk score $($Verdict.Score)/100)")
    [void]$out.AppendLine(("=" * 72))
    [void]$out.AppendLine("")

    $ordered = @($FindingSet | Sort-Object @{ Expression = { $SeverityRank[$_.Severity] }; Descending = $true }, Module)
    foreach ($sev in @("Critical","High","Medium","Low","Info")) {
        $group = @($ordered | Where-Object { $_.Severity -eq $sev })
        if (-not $group) { continue }
        [void]$out.AppendLine("[$($sev.ToUpper())] - $($group.Count) finding(s)")
        [void]$out.AppendLine(("-" * 72))
        foreach ($f in $group) {
            [void]$out.AppendLine("* $($f.Title)   ($($f.Module))")
            if ($f.Detail) { [void]$out.AppendLine("    $($f.Detail)") }
            foreach ($e in @($f.Evidence)) { [void]$out.AppendLine("      $e") }
            [void]$out.AppendLine("")
        }
        [void]$out.AppendLine("")
    }

    if ($SkippedModules -and $SkippedModules.Count -gt 0) {
        [void]$out.AppendLine("MODULES THAT COULD NOT RUN")
        [void]$out.AppendLine(("-" * 72))
        foreach ($s in $SkippedModules) { [void]$out.AppendLine("  $s") }
        [void]$out.AppendLine("")
    }

    [void]$out.AppendLine("NOT COVERED BY THIS TOOL")
    [void]$out.AppendLine(("-" * 72))
    [void]$out.AppendLine("  Hardware-firmware mouse macros, a second physical PC, phone-based")
    [void]$out.AppendLine("  automation and anything already wiped by a clean Windows reinstall")
    [void]$out.AppendLine("  cannot be seen from software. This report is evidence, not a verdict.")

    Set-Content -LiteralPath $path -Value $out.ToString() -Encoding UTF8 -Force
    return $path
}

# Reports
function Send-CheckReport {
    param($FindingSet, $Verdict, [string]$ReportPath)
    if (-not $WebhookUrls) { return }
    $head = (Get-MachineHeader) -join "`n"
    Report-Run "PC check complete - $($Verdict.Band) (risk $($Verdict.Score)/100)" -Detail $head

    $notable = @($FindingSet | Where-Object { $_.Severity -ne "Info" } |
        Sort-Object @{ Expression = { $SeverityRank[$_.Severity] }; Descending = $true })
    if (-not $notable) { Report-Run "PC check findings" -Detail "nothing above Info severity"; return }

    $buf = ""
    $sent = 0
    foreach ($f in $notable) {
        $block = "[$($f.Severity.ToUpper())] $($f.Title)`n  $($f.Detail)"
        foreach ($e in @($f.Evidence | Select-Object -First 4)) { $block += "`n    $e" }
        $block += "`n"
        if ($block.Length -gt 900) { $block = $block.Substring(0, 900) + "...`n" }
        if (($buf.Length + $block.Length) -gt 900) {
            $sent++
            if ($sent -gt 8) { Report-Run "PC check findings (truncated)" -Detail "more findings in $ReportPath"; return }
            Report-Run "PC check findings ($sent)" -Detail $buf
            $buf = ""
        }
        $buf += $block
    }
    if ($buf) { Report-Run "PC check findings ($($sent + 1))" -Detail $buf }
}

# Helpers

# Helpers
# Live
$SigCache = [hashtable]::Synchronized(@{})
function Get-SignatureInfo {
    param([string]$Path)
    if (-not $Path) { return @{ Status = "unknown"; Signer = "" } }
    $key = $Path.ToLowerInvariant()
    if ($SigCache.ContainsKey($key)) { return $SigCache[$key] }
    $info = @{ Status = "unknown"; Signer = "" }
    try {
        if (Test-Path -LiteralPath $Path) {
            $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
            $info.Status = switch ("$($s.Status)") {
                "Valid"              { "valid" }
                "NotSigned"          { "unsigned" }
                "UnknownError"       { "unsigned" }
                "HashMismatch"       { "tampered" }
                "NotTrusted"         { "untrusted" }
                default              { "$($s.Status)".ToLowerInvariant() }
            }
            if ($s.SignerCertificate) { $info.Signer = "$($s.SignerCertificate.Subject)" -replace '^CN=([^,]+).*$', '$1' }
        } else {
            $info.Status = "missing"
        }
    } catch { $info.Status = "unreadable" }
    $SigCache[$key] = $info
    return $info
}

# Cheats
$SuspectPaths = @(
    "$env:TEMP", "$env:LOCALAPPDATA\Temp", "$env:APPDATA", "$env:LOCALAPPDATA",
    "$env:ProgramData", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Documents", "$env:PUBLIC", "C:\`$Recycle.Bin"
)
function Test-SuspectPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    $p = $Path.ToLowerInvariant()
    foreach ($s in $SuspectPaths) {
        if (-not $s) { continue }
        if ($p.StartsWith($s.ToLowerInvariant())) { return $true }
    }
    return $false
}

# Helpers
# Launcher
function Search-FileMarkers {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Markers,
        [int]$MaxBytes = 40MB
    )
    $hits = @()
    try {
        $fi = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($fi.Length -eq 0 -or $fi.Length -gt $MaxBytes) { return $hits }
        $bytes = [System.IO.File]::ReadAllBytes($fi.FullName)
        $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
        $wide  = [System.Text.Encoding]::Unicode.GetString($bytes)
        foreach ($m in $Markers) {
            if (-not $m) { continue }
            if ($ascii.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $wide.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += $m
            }
        }
        if ($fi.Extension -match '^\.(jar|zip)$') {
            $hits += @(Search-ZipEntryMarkers -Path $fi.FullName -Markers $Markers)
        }
    } catch {}
    return @($hits | Select-Object -Unique)
}

function Search-ZipEntryMarkers {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Markers,
        [int]$MaxEntryBytes = 2MB
    )
    $hits = @()
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $entryNames = @($zip.Entries | ForEach-Object { "$($_.FullName)" })
            $entryBlob = $entryNames -join "`n"
            foreach ($m in $Markers) {
                if (-not $m) { continue }
                if ($entryBlob.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hits += $m }
            }

            $readEntryText = {
                param([string]$Name)
                $entry = $zip.GetEntry($Name)
                if (-not $entry -or $entry.Length -gt $MaxEntryBytes) { return "" }
                $stream = $entry.Open()
                try {
                    $ms = New-Object IO.MemoryStream
                    $stream.CopyTo($ms)
                    $bytes = $ms.ToArray()
                    return ([Text.Encoding]::ASCII.GetString($bytes) + "`n" + [Text.Encoding]::Unicode.GetString($bytes))
                } finally {
                    if ($ms) { $ms.Dispose() }
                    $stream.Dispose()
                }
            }

            foreach ($entry in @($zip.Entries | Where-Object { $_.Length -gt 0 -and $_.Length -le $MaxEntryBytes -and $_.FullName -match '\.(json|toml|info|mcmeta|mf|class)$|^META-INF/MANIFEST\.MF$' } | Select-Object -First 80)) {
                $stream = $entry.Open()
                try {
                    $ms = New-Object IO.MemoryStream
                    $stream.CopyTo($ms)
                    $bytes = $ms.ToArray()
                    $text = [Text.Encoding]::ASCII.GetString($bytes) + "`n" + [Text.Encoding]::Unicode.GetString($bytes)
                    foreach ($m in $Markers) {
                        if (-not $m) { continue }
                        if ($text.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hits += $m }
                    }
                } finally {
                    if ($ms) { $ms.Dispose() }
                    $stream.Dispose()
                }
            }

            $manifest = & $readEntryText 'META-INF/MANIFEST.MF'
            $fabric = & $readEntryText 'fabric.mod.json'
            $modsToml = & $readEntryText 'META-INF/mods.toml'
            $addon3 = & $readEntryText 'addon3.json'
            $addon4 = & $readEntryText 'addon4.json'
            $hasDoomsdayLayout = @('fabric.mod.json','mcmod.info','META-INF/mods.toml','mod_d.class','net/java/ag.class','net/java/m.class','addon3.json','addon4.json') |
                Where-Object { $entryNames -contains $_ }
            if ($hasDoomsdayLayout.Count -ge 6) { $hits += 'DoomsDay loader structure' }
            if ($manifest.IndexOf('Premain-Class: net.java.ag', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $manifest.IndexOf('Main-Class: net.java.m', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $manifest.IndexOf('Can-Retransform-Classes: true', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += 'DoomsDay javaagent manifest'
            }
            if ($fabric.IndexOf('"id":"dd"', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $modsToml.IndexOf('modId="dd"', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += 'DoomsDay dd mod metadata'
            }
            if (($addon3 + $addon4).IndexOf('mainClass":"net.java.', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                ($addon3 + $addon4).IndexOf('Full Bright', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += 'DoomsDay addon metadata'
            }
        } finally {
            if ($zip) { $zip.Dispose() }
        }
    } catch {}
    return @($hits | Select-Object -Unique)
}

function Search-ProcessMemoryMarkers {
    param(
        [Parameter(Mandatory=$true)][int]$ProcessId,
        [Parameter(Mandatory=$true)]$Signatures,
        [int]$MinMarkers = 2,
        [int64]$MaxBytes = 256MB
    )
    if (-not ("RevsNative.Memory" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace RevsNative {
    public static class Memory {
        [StructLayout(LayoutKind.Sequential)]
        public struct MEMORY_BASIC_INFORMATION {
            public IntPtr BaseAddress;
            public IntPtr AllocationBase;
            public UInt32 AllocationProtect;
            public IntPtr RegionSize;
            public UInt32 State;
            public UInt32 Protect;
            public UInt32 Type;
        }

        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr OpenProcess(UInt32 access, bool inheritHandle, Int32 processId);

        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool ReadProcessMemory(IntPtr process, IntPtr baseAddress, byte[] buffer, UIntPtr size, out UIntPtr bytesRead);

        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern UIntPtr VirtualQueryEx(IntPtr process, IntPtr address, out MEMORY_BASIC_INFORMATION info, UIntPtr length);

        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool CloseHandle(IntPtr handle);
    }
}
"@
    }

    $markerToClients = @{}
    $clientConfidence = @{}
    $clientMinMarkers = @{}
    foreach ($sig in @($Signatures)) {
        $clientName = "$($sig.Name)"
        if (-not $clientName) { continue }
        $clientConfidence[$clientName] = "$($sig.Confidence)"
        $clientMinMarkers[$clientName] = if ($sig.MemoryMinMarkers) { [int]$sig.MemoryMinMarkers } else { $MinMarkers }
        foreach ($m in @(@($sig.Markers) + @($sig.Strings))) {
            if (-not $m -or "$m".Length -lt 4) { continue }
            if ($CheatSignatureBlacklist -contains $m) { continue }
            if (-not $markerToClients.ContainsKey($m)) {
                $markerToClients[$m] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $markerToClients[$m].Contains($clientName)) {
                $markerToClients[$m].Add($clientName)
            }
        }
    }
    $markers = @($markerToClients.Keys)
    if (-not $markers) { return @() }

    $PROCESS_QUERY_INFORMATION = 0x0400
    $PROCESS_VM_READ = 0x0010
    $MEM_COMMIT = 0x1000
    $PAGE_GUARD = 0x100
    $PAGE_NOACCESS = 0x01
    $maxChunk = 1MB
    $seen = @{}
    $scanned = [int64]0

    $h = [RevsNative.Memory]::OpenProcess($PROCESS_QUERY_INFORMATION -bor $PROCESS_VM_READ, $false, $ProcessId)
    if ($h -eq [IntPtr]::Zero) { return @() }
    try {
        $addr = [int64]0
        $mbiSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][RevsNative.Memory+MEMORY_BASIC_INFORMATION])
        while ($scanned -lt $MaxBytes) {
            $mbi = New-Object RevsNative.Memory+MEMORY_BASIC_INFORMATION
            $q = [RevsNative.Memory]::VirtualQueryEx($h, [IntPtr]$addr, [ref]$mbi, [UIntPtr]$mbiSize)
            if ($q -eq [UIntPtr]::Zero) { break }

            $base = $mbi.BaseAddress.ToInt64()
            $region = $mbi.RegionSize.ToInt64()
            if ($region -le 0) { break }
            $readable = ($mbi.State -eq $MEM_COMMIT) -and (($mbi.Protect -band $PAGE_GUARD) -eq 0) -and (($mbi.Protect -band $PAGE_NOACCESS) -eq 0)
            if ($readable) {
                $offset = [int64]0
                while ($offset -lt $region -and $scanned -lt $MaxBytes) {
                    $toRead = [int][Math]::Min($maxChunk, [Math]::Min($region - $offset, $MaxBytes - $scanned))
                    $buf = New-Object byte[] $toRead
                    $bytesRead = [UIntPtr]::Zero
                    if ([RevsNative.Memory]::ReadProcessMemory($h, [IntPtr]($base + $offset), $buf, [UIntPtr]$toRead, [ref]$bytesRead)) {
                        $n = [int]$bytesRead.ToUInt64()
                        if ($n -gt 0) {
                            if ($n -lt $buf.Length) { [Array]::Resize([ref]$buf, $n) }
                            $ascii = [System.Text.Encoding]::ASCII.GetString($buf)
                            $wide  = [System.Text.Encoding]::Unicode.GetString($buf)
                            foreach ($m in $markers) {
                                if ($ascii.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                                    $wide.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                    foreach ($client in @($markerToClients[$m])) {
                                        if (-not $seen.ContainsKey($client)) { $seen[$client] = New-Object System.Collections.Generic.List[string] }
                                        if (-not $seen[$client].Contains($m)) { $seen[$client].Add($m) }
                                    }
                                }
                            }
                            $scanned += $n
                        }
                    }
                    $offset += $toRead
                }
            }

            $next = $base + $region
            if ($next -le $addr) { break }
            $addr = $next
        }
    } finally {
        [void][RevsNative.Memory]::CloseHandle($h)
    }

    $hits = @()
    foreach ($client in @($seen.Keys)) {
        $found = @($seen[$client])
        $needed = if ($clientMinMarkers.ContainsKey($client)) { [int]$clientMinMarkers[$client] } else { $MinMarkers }
        if ($found.Count -ge $needed) {
            $hits += [pscustomobject]@{
                Client     = $client
                Confidence = $clientConfidence[$client]
                MarkerCount = $found.Count
                Markers    = @($found)
                Evidence   = "$client -> markers in live java memory: $($found -join ', ')"
            }
        }
    }
    return @($hits | Sort-Object MarkerCount, Client -Descending)
}

# Cheats
function Invoke-ParallelCheatContentScan {
    param(
        [object[]]$Candidates,
        [hashtable]$MarkerMap,
        [int]$Throttle = 0
    )
    $paths = @($Candidates | ForEach-Object { $_.FullName } | Where-Object { $_ })
    $markers = @($MarkerMap.Keys | Where-Object { $_ })
    if (-not $paths -or -not $markers) { return @() }

    if ($Throttle -lt 1) {
        $Throttle = [Math]::Min([Math]::Max([Environment]::ProcessorCount, 2), 8)
    }
    $Throttle = [Math]::Min($Throttle, $paths.Count)
    $chunkCount = [Math]::Min($paths.Count, [Math]::Max($Throttle * 2, 1))
    $chunks = @()
    for ($i = 0; $i -lt $chunkCount; $i++) {
        $chunks += ,(New-Object System.Collections.Generic.List[string])
    }
    for ($i = 0; $i -lt $paths.Count; $i++) {
        $chunks[$i % $chunkCount].Add($paths[$i])
    }

    $worker = {
        param([string[]]$Paths, [string[]]$Markers, [hashtable]$Map)
        $hitsOut = @()
        foreach ($path in @($Paths)) {
            $found = @()
            try {
                $fi = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ($fi.Length -eq 0 -or $fi.Length -gt 40MB) { continue }
                $bytes = [System.IO.File]::ReadAllBytes($fi.FullName)
                $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
                $wide  = [System.Text.Encoding]::Unicode.GetString($bytes)
                foreach ($m in $Markers) {
                    if (-not $m) { continue }
                    if ($ascii.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                        $wide.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $found += $m
                    }
                }
                if ($fi.Extension -match '^\.(jar|zip)$') {
                    try {
                        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                        $zip = [IO.Compression.ZipFile]::OpenRead($fi.FullName)
                        try {
                            $entryNames = @($zip.Entries | ForEach-Object { "$($_.FullName)" })
                            $entryBlob = $entryNames -join "`n"
                            foreach ($m in $Markers) {
                                if (-not $m) { continue }
                                if ($entryBlob.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found += $m }
                            }

                            $metadata = @{}
                            foreach ($entry in @($zip.Entries | Where-Object { $_.Length -gt 0 -and $_.Length -le 2MB -and $_.FullName -match '\.(json|toml|info|mcmeta|mf|class)$|^META-INF/MANIFEST\.MF$' } | Select-Object -First 80)) {
                                $stream = $entry.Open()
                                try {
                                    $ms = New-Object IO.MemoryStream
                                    $stream.CopyTo($ms)
                                    $entryBytes = $ms.ToArray()
                                    $text = [Text.Encoding]::ASCII.GetString($entryBytes) + "`n" + [Text.Encoding]::Unicode.GetString($entryBytes)
                                    $metadata[$entry.FullName] = $text
                                    foreach ($m in $Markers) {
                                        if (-not $m) { continue }
                                        if ($text.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found += $m }
                                    }
                                } finally {
                                    if ($ms) { $ms.Dispose() }
                                    $stream.Dispose()
                                }
                            }

                            $layoutHits = @('fabric.mod.json','mcmod.info','META-INF/mods.toml','mod_d.class','net/java/ag.class','net/java/m.class','addon3.json','addon4.json') |
                                Where-Object { $entryNames -contains $_ }
                            if ($layoutHits.Count -ge 6) { $found += 'DoomsDay loader structure' }
                            $manifest = "$($metadata['META-INF/MANIFEST.MF'])"
                            if ($manifest.IndexOf('Premain-Class: net.java.ag', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                                $manifest.IndexOf('Main-Class: net.java.m', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                                $manifest.IndexOf('Can-Retransform-Classes: true', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $found += 'DoomsDay javaagent manifest'
                            }
                            $fabric = "$($metadata['fabric.mod.json'])"
                            $modsToml = "$($metadata['META-INF/mods.toml'])"
                            if ($fabric.IndexOf('"id":"dd"', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                                $modsToml.IndexOf('modId="dd"', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $found += 'DoomsDay dd mod metadata'
                            }
                            $addons = "$($metadata['addon3.json'])`n$($metadata['addon4.json'])"
                            if ($addons.IndexOf('mainClass":"net.java.', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                                $addons.IndexOf('Full Bright', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $found += 'DoomsDay addon metadata'
                            }
                        } finally {
                            if ($zip) { $zip.Dispose() }
                        }
                    } catch {}
                }
            } catch {}
            $found = @($found | Select-Object -Unique)
            if ($found.Count -ge 2) {
                $clients = @($found | ForEach-Object { $Map[$_] } | Where-Object { $_ } | Select-Object -Unique)
                $hitsOut += "$path  ->  $($clients -join ', ')  [markers: $($found -join ', ')]"
            }
        }
        return $hitsOut
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $Throttle)
    $pool.ApartmentState = "MTA"
    $pool.Open()
    $jobs = @()
    try {
        foreach ($chunk in $chunks) {
            if ($chunk.Count -eq 0) { continue }
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker).AddArgument([string[]]$chunk.ToArray()).AddArgument([string[]]$markers).AddArgument($MarkerMap)
            $jobs += [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() }
        }

        $results = @()
        foreach ($job in $jobs) {
            try { $results += @($job.PowerShell.EndInvoke($job.Handle)) }
            catch {}
            finally { $job.PowerShell.Dispose() }
        }
        return $results
    } finally {
        $pool.Close()
        $pool.Dispose()
    }
}

# Cheats
function Invoke-ParallelCheatArtifactScan {
    param(
        [object[]]$Signatures,
        [hashtable]$RunningProcesses,
        [int]$Throttle = 0
    )
    if (-not $Signatures) { return @() }
    if ($Throttle -lt 1) {
        $Throttle = [Math]::Min([Math]::Max([Environment]::ProcessorCount, 2), 8)
    }
    $Throttle = [Math]::Min($Throttle, @($Signatures).Count)

    $worker = {
        param($Sig, [hashtable]$Running)
        $hits = @()
        foreach ($proc in @($Sig.Processes)) {
            if (-not $proc) { continue }
            $key = ($proc -replace '\.exe$','').ToLowerInvariant()
            if ($Running.ContainsKey($key)) { $hits += $Running[$key] }
        }
        foreach ($path in @($Sig.Paths)) {
            if (-not $path) { continue }
            $expanded = [Environment]::ExpandEnvironmentVariables($path)
            $matches = @()
            try {
                if ($expanded -match '[\*\?]') {
                    $matches = @(Resolve-Path -Path $expanded -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath })
                } elseif (Test-Path -LiteralPath $expanded) {
                    $matches = @($expanded)
                }
            } catch {}
            foreach ($m in @($matches | Select-Object -Unique | Select-Object -First 20)) {
                try {
                    $item = Get-Item -LiteralPath $m -Force -ErrorAction Stop
                    $hits += "on disk: $m (last written $($item.LastWriteTime))"
                } catch {
                    $hits += "on disk: $m"
                }
            }
        }
        foreach ($reg in @($Sig.Registry)) {
            if (-not $reg) { continue }
            if (Test-Path $reg) { $hits += "registry key present: $reg" }
        }
        if ($hits) {
            [pscustomobject]@{
                Name       = $Sig.Name
                Confidence = $Sig.Confidence
                Hits       = @($hits)
            }
        }
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $Throttle)
    $pool.ApartmentState = "MTA"
    $pool.Open()
    $jobs = @()
    try {
        foreach ($sig in @($Signatures)) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker).AddArgument($sig).AddArgument($RunningProcesses)
            $jobs += [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() }
        }

        $results = @()
        foreach ($job in $jobs) {
            try { $results += @($job.PowerShell.EndInvoke($job.Handle)) }
            catch {}
            finally { $job.PowerShell.Dispose() }
        }
        return $results
    } finally {
        $pool.Close()
        $pool.Dispose()
    }
}

# Live
function Get-JavaProcesses {
    $out = @()
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -match "^(javaw?|java)\.exe$" -or "$($_.CommandLine)" -match "\.jar(\b|""|'|\s)" }
        foreach ($p in $procs) {
            $out += [pscustomobject]@{
                Pid         = [int]$p.ProcessId
                Name        = "$($p.Name)"
                Path        = "$($p.ExecutablePath)"
                CommandLine = "$($p.CommandLine)"
                ParentPid   = [int]$p.ParentProcessId
                Started     = $p.CreationDate
            }
        }
    } catch {}
    return $out
}

# Modules

# Live
# Reports
function Invoke-ScanModule {
    param($Module)
    Set-Progress "Running: $($Module.Name)"
    Write-Log "Module: $($Module.Name)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $res = @(& $Module.Fn)
        $sw.Stop()
        Write-Log "$($Module.Name) finished in $([int]$sw.Elapsed.TotalSeconds)s - $($res.Count) finding(s)"
        return @{ Findings = $res; Error = $null }
    } catch {
        $sw.Stop()
        $msg = $_.Exception.Message
        Write-Log "$($Module.Name) could not run: $msg"
        return @{ Findings = @(); Error = $msg }
    }
}

# Live
function Invoke-FullCheck {
    Clear-Findings
    $FullBtn.Dispatcher.Invoke([Action]{ $FullBtn.IsEnabled = $false; $FullBtn.Content = "Checking..." })
    Set-Status "Automatic PC check running - do not close Minecraft." "busy"
    $started = Get-Date

    $auto = @($ScanModules | Where-Object { $_.Auto } | Sort-Object Order)
    $skipped = @()
    $i = 0
    foreach ($m in $auto) {
        $i++
        Set-Progress "[$i/$($auto.Count)] $($m.Name)"
        $r = Invoke-ScanModule $m
        if ($r.Error) { $skipped += "$($m.Name) - $($r.Error)" }
        foreach ($f in $r.Findings) { Add-Finding $f }
    }

    $all = @($Findings)
    $verdict = Get-Verdict $all
    $counts = @{}
    foreach ($sev in @("Critical","High","Medium","Low")) {
        $counts[$sev] = @($all | Where-Object { $_.Severity -eq $sev }).Count
    }
    $detail = "$($counts['Critical']) critical, $($counts['High']) high, $($counts['Medium']) medium, $($counts['Low']) low across $($auto.Count) modules"
    if ($skipped.Count -gt 0) { $detail += " - $($skipped.Count) module(s) could not run" }
    Show-Verdict $verdict $detail

    $path = $null
    try {
        $path = Write-CheckReport -FindingSet $all -Verdict $verdict -SkippedModules $skipped
        $ReportBtn.Dispatcher.Invoke([Action]{ $ReportBtn.Tag = $path; $ReportBtn.Visibility = "Visible" })
        Write-Log "Report written to $path"
    } catch {
        Write-Log "Could not write the report file: $($_.Exception.Message)"
    }

    Send-CheckReport -FindingSet $all -Verdict $verdict -ReportPath $path

    $elapsed = [int]((Get-Date) - $started).TotalSeconds
    Set-Progress "Done in ${elapsed}s - $detail"
    $state = if ($verdict.Band -eq "CLEAN") { "ok" } else { "err" }
    Set-Status "PC check complete - $($verdict.Band) (risk $($verdict.Score)/100)." $state
    $FullBtn.Dispatcher.Invoke([Action]{ $FullBtn.IsEnabled = $true; $FullBtn.Content = "Run full check" })
}

# UI
function Invoke-SingleModule {
    param([string]$Key)
    $m = @($ScanModules | Where-Object { $_.Key -eq $Key })[0]
    if (-not $m) { Set-Status "Unknown scan module." "err"; return }
    Set-Status "$($m.Name) running..." "busy"
    $r = Invoke-ScanModule $m
    foreach ($f in $r.Findings) { Add-Finding $f }
    if ($r.Error) {
        Set-Progress "$($m.Name) could not run - $($r.Error)"
        Set-Status "$($m.Name) could not run." "err"
        return
    }
    $notable = @($r.Findings | Where-Object { $_.Severity -ne "Info" })
    $verdict = Get-Verdict @($Findings)
    Show-Verdict $verdict "$($m.Name): $($notable.Count) notable finding(s)"
    if ($notable.Count -gt 0) { Set-Status "$($m.Name) done - $($notable.Count) finding(s)." "err" }
    else                      { Set-Status "$($m.Name) done - nothing notable." "ok" }
}

# Registry
function Invoke-RegistryScan {
    param([string]$Term)
    $t = $Term.Trim()
    if (-not $t) { Write-Log "Type something to search for first."; Set-Status "Enter a word to search for." "ok"; return }
    Set-Status "Scanning the registry for `"$t`"..." "busy"
    Write-Log "Registry scan started for: $t"
    $found = $false; $summary = @()
    foreach ($root in $RegSearchRoots) {
        $out = & reg query "$root" /f "$t" /s 2>$null | Out-String
        if ($out -and ($out -notmatch "0 match") -and ($out -match "match\(es\) found")) {
            $found = $true; Write-Log "Match in $root"; $summary += "--- $root ---"
            foreach ($line in ($out -split "`r?`n")) {
                $l = $line.Trim()
                if ($l -and ($l -notmatch "^End of search")) { $summary += "  $l" }
            }
        }
    }
    if ($found) { Set-Status "Registry scan done - matches found for `"$t`" (see Discord/report)." "ok" }
    else        { Set-Status "Registry scan done - no matches for `"$t`"." "ok" }
    Report-Run "Registry scan: $t" -Detail $(if ($found) { ($summary -join "`n") } else { "no matches" })
}

# Cheats
# Live
function Invoke-JavaJarScan {
    Set-Status "Scanning running processes for .jar..." "busy"
    Write-Log "Java/.jar process scan started."
    $hits = @()
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop
    } catch {
        Write-Log "Couldn't read process list: $($_.Exception.Message)"
        Set-Status "Process scan failed - try running as admin." "err"
        Report-Run "Java/.jar process scan" -Detail "failed: $($_.Exception.Message)"; return
    }
    foreach ($p in $procs) {
        $cl   = "$($p.CommandLine)"
        $name = "$($p.Name)"
        $isJar  = $cl -match "\.jar(\b|""|'|\s)"
        $isJava = $name -match "^(javaw?|java)\.exe$"
        # Cheats
        $svcJar = ($name -match "^svchost\.exe$") -and $isJar
        if ($isJar -or $isJava -or $svcJar) {
            $tag = if ($svcJar) { "[SUSPICIOUS svchost+jar] " } elseif ($isJar) { "[jar] " } else { "[java host] " }
            $jarRefs = ([regex]::Matches($cl, '[^\s"'']+\.jar')) | ForEach-Object { $_.Value } | Select-Object -Unique
            $line = "$tag PID $($p.ProcessId)  $name"
            if ($jarRefs) { $line += "  ->  " + ($jarRefs -join ", ") }
            $hits += $line
            Write-Log $line
        }
    }
    if ($hits) { Set-Status "Process scan done - $($hits.Count) hit(s), see report." "ok" }
    else       { Set-Status "Process scan done - no .jar running in any process." "ok" }
    Report-Run "Java/.jar process scan" -Detail $(if ($hits) { ($hits -join "`n") } else { "no .jar found running in any process" })
}

# Cheats
function Invoke-ModInjectionScan {
    Set-Status "Checking mods for injection..." "busy"
    Write-Log "Mod injection scan started."
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    if (-not ($SelectedModFolder -and (Test-Path -LiteralPath $SelectedModFolder))) {
        Write-Log "No pasted mod folder path selected."
        Set-Status "Paste a mod folder path first." "err"
        Report-Run "Mod injection scan" -Detail "skipped - no pasted mod folder path selected"; return
    }
    $modDirs = @($SelectedModFolder)

    if (-not $modDirs) {
        Write-Log "No mod folders found."
        Set-Status "No mod folders found." "ok"
        Report-Run "Mod injection scan" -Detail "no mod folders found"; return
    }

    $jars = Get-ChildItem -Path $modDirs -Recurse -Filter *.jar -ErrorAction SilentlyContinue
    Write-Log "Found $($jars.Count) mod .jar file(s). Inspecting..."
    $findings = @()
    foreach ($j in $jars) {
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($j.FullName)
            try {
                $flags = @()
                $man = $zip.Entries | Where-Object { $_.FullName -eq "META-INF/MANIFEST.MF" } | Select-Object -First 1
                if ($man) {
                    $sr = New-Object System.IO.StreamReader($man.Open())
                    $text = $sr.ReadToEnd(); $sr.Close()
                    if ($text -match "(?im)^(Premain-Class|Agent-Class)\s*:") { $flags += "java agent (injects into a running JVM)" }
                    if ($text -match "(?im)^Can-Retransform-Classes\s*:\s*true") { $flags += "can retransform classes" }
                    if ($text -match "(?im)^Can-Redefine-Classes\s*:\s*true")   { $flags += "can redefine classes" }
                }
                if ($zip.Entries | Where-Object { $_.FullName -match "\.jar$" }) { $flags += "nested .jar inside" }
                if ($zip.Entries | Where-Object { $_.FullName -match "(?i)(inject|agent|transform|premain|hook)\w*\.class$" }) { $flags += "injection-style class names" }
                if ($flags) {
                    $line = "$($j.Name)  ->  " + ($flags -join "; ")
                    $findings += $line; Write-Log $line
                }
            } finally { $zip.Dispose() }
        } catch {
            Write-Log "Couldn't read $($j.Name): $($_.Exception.Message)"
        }
    }
    if ($findings) { Set-Status "Mod scan done - $($findings.Count) mod(s) look injected, see report." "err" }
    else           { Set-Status "Mod scan done - no injection signs in $($jars.Count) mod(s)." "ok" }
    Report-Run "Mod injection scan ($($jars.Count) jars)" -Detail $(if ($findings) { ($findings -join "`n") } else { "no injection signs found" })
}

# Live
# UI

# Live
$KnownGoodModuleHints = @(
    "\windows\system32\", "\windows\syswow64\", "\windows\winsxs\",
    "\windows\assembly\", "\windows\microsoft.net\", "\program files\java\",
    "\program files (x86)\java\", "\program files\eclipse adoptium\",
    "\program files\amazon corretto\", "\program files\zulu\",
    "\appdata\roaming\modrinthapp\meta\natives\",
    "\appdata\roaming\modrinthapp\meta\java_versions\"
)
function Test-KnownGoodModulePath {
    param([string]$Path)
    if (-not $Path) { return $false }
    $p = $Path.ToLowerInvariant()
    foreach ($h in $KnownGoodModuleHints) { if ($p.Contains($h)) { return $true } }
    $leaf = [IO.Path]::GetFileName($p)
    if ($p.Contains("\appdata\local\temp\") -and $leaf -match "^(lwjgl|glfw|openal|jemalloc|jna|jansi|libspeex|librrnoise|libjline).*\.dll$") {
        return $true
    }
    return $false
}

function Get-KnownJavaAgentName {
    param([string]$Path)
    if (-not $Path) { return $null }
    $p = $Path.ToLowerInvariant()
    if ($p -match "\\theseus\.jar$" -or $p.Contains("\modrinthapp\")) { return "Modrinth launcher agent" }
    if ($p.Contains("\lunarclient\")) { return "Lunar Client launcher agent" }
    if ($p.Contains("\badlion client\")) { return "Badlion Client launcher agent" }
    if ($p.Contains("\feather client\")) { return "Feather Client launcher agent" }
    if ($p.Contains("\prismlauncher\")) { return "Prism Launcher agent" }
    if ($p.Contains("\multimc\")) { return "MultiMC launcher agent" }
    return $null
}

function Get-ClientNameFromText {
    param(
        [string]$Text,
        [object[]]$Signatures
    )
    if (-not $Text) { return $null }
    $best = $null
    $bestCount = 0
    foreach ($sig in @($Signatures)) {
        $count = 0
        foreach ($m in @(@($sig.Markers) + @($sig.Strings) + @($sig.Files))) {
            if (-not $m -or "$m".Length -lt 4) { continue }
            if ($CheatSignatureBlacklist -contains $m) { continue }
            if ($Text.IndexOf("$m", [StringComparison]::OrdinalIgnoreCase) -ge 0) { $count++ }
        }
        if ($count -gt $bestCount) {
            $bestCount = $count
            $best = "$($sig.Name)"
        }
    }
    if ($bestCount -gt 0) { return $best }
    return $null
}

# Live
function Invoke-LiveInjectionScan {
    $out = @()
    $java = @(Get-JavaProcesses)
    if (-not $java) {
        $out += New-Finding -Module "Live injection" -Title "No Java process is running" -Severity "Info" `
            -Detail "Minecraft was not running during the check, so live injection could not be observed. Volatile evidence is unavailable."
        return $out
    }

    $out += New-Finding -Module "Live injection" -Title "$($java.Count) Java process(es) running" -Severity "Info" `
        -Detail "Captured at $(Get-Date -Format 'HH:mm:ss')." `
        -Evidence @($java | ForEach-Object { "PID $($_.Pid) $($_.Name) - $($_.Path)" })

    foreach ($p in $java) {
        $cl = "$($p.CommandLine)"

        # Live
        # Helpers
        $agents = @([regex]::Matches($cl, '-(?:javaagent|agentpath|agentlib):([^\s"]+)') | ForEach-Object { $_.Groups[1].Value })
        $knownAgentNames = @()
        foreach ($a in $agents) {
            $file = ($a -split "=")[0]
            $knownAgent = Get-KnownJavaAgentName $file
            $sig = Get-SignatureInfo $file
            if ($knownAgent) {
                $knownAgentNames += $knownAgent
                $out += New-Finding -Module "Live injection" -Title "$knownAgent loaded into PID $($p.Pid)" -Severity "Info" `
                    -Detail "This launcher uses a JVM agent during normal startup. Signature: $($sig.Status) $($sig.Signer)" `
                    -Evidence @($file)
                continue
            }

            $clientFromAgent = Get-ClientNameFromText -Text $file -Signatures $CheatSignatures
            $sev = if (Test-SuspectPath $file) { "Critical" } else { "High" }
            $title = if ($clientFromAgent) { "$clientFromAgent Java agent loaded into PID $($p.Pid)" } else { "Unknown Java agent loaded into PID $($p.Pid)" }
            $out += New-Finding -Module "Live injection" -Title $title -Severity $sev `
                -Detail "The JVM was started with an agent, which can rewrite game classes at runtime. Signature: $($sig.Status) $($sig.Signer)" `
                -Evidence @($file)
        }

        if ($cl -match "-XX:\+DisableAttachMechanism") {
            $out += New-Finding -Module "Live injection" -Title "JVM attach mechanism disabled on PID $($p.Pid)" -Severity "High" `
                -Detail "This flag blocks tools from inspecting the running JVM. No normal Minecraft launcher sets it; it is a standard way to stop an injection check."
        }
        if ($cl -match "-Xbootclasspath") {
            $out += New-Finding -Module "Live injection" -Title "Boot classpath override on PID $($p.Pid)" -Severity "Medium" `
                -Detail "Classes are being loaded ahead of the JVM's own, which can replace game code."
        }

        # Live
        foreach ($ev in @("JAVA_TOOL_OPTIONS","_JAVA_OPTIONS","JDK_JAVA_OPTIONS")) {
            $val = [Environment]::GetEnvironmentVariable($ev, "User")
            if (-not $val) { $val = [Environment]::GetEnvironmentVariable($ev, "Machine") }
            if ($val) {
                $sev = if ($val -match "javaagent|agentpath|agentlib|bootclasspath") { "Critical" } else { "Medium" }
                $out += New-Finding -Module "Live injection" -Title "$ev environment variable is set" -Severity $sev `
                    -Detail "This silently adds JVM options to every Java process, including agents that would not show on the launcher's command line." `
                    -Evidence @("$ev = $val")
            }
        }

        # Cheats
        # Helpers
        # Journal
        try {
            $proc = Get-Process -Id $p.Pid -ErrorAction Stop
            $mods = @($proc.Modules)
            $bad = @()
            $gone = @()
            foreach ($m in $mods) {
                $mp = "$($m.FileName)"
                if (-not $mp) { continue }
                if (Test-KnownGoodModulePath $mp) { continue }
                if (-not (Test-Path -LiteralPath $mp)) { $gone += $mp; continue }
                $sig = Get-SignatureInfo $mp
                if ($sig.Status -ne "valid" -and (Test-SuspectPath $mp)) {
                    $bad += "$mp [$($sig.Status)]"
                }
            }
            if ($gone) {
                $out += New-Finding -Module "Live injection" -Title "Module loaded in PID $($p.Pid) has no file on disk" -Severity "Critical" `
                    -Detail "Code is mapped into the Java process but its file is gone. That is the signature of a loader that deletes itself after injecting." `
                    -Evidence $gone
            }
            if ($bad) {
                $out += New-Finding -Module "Live injection" -Title "Unsigned module(s) inside Java process $($p.Pid)" -Severity "High" `
                    -Detail "Unsigned native code loaded from a user-writable folder. Legitimate launcher and JRE components are signed and live under Program Files or Windows." `
                    -Evidence $bad
            }
            $out += New-Finding -Module "Live injection" -Title "PID $($p.Pid) module count" -Severity "Info" `
                -Detail "$($mods.Count) modules loaded."
        } catch {
            $out += New-Finding -Module "Live injection" -Title "Could not read modules of PID $($p.Pid)" -Severity "Low" `
                -Detail "The process refused inspection: $($_.Exception.Message). A process that blocks module enumeration while the tool runs as admin is itself worth a manual look."
        }

        # Live
        # Cheats
        try {
            $attach = @((Get-Process -Id $p.Pid -ErrorAction Stop).Modules |
                Where-Object { "$($_.ModuleName)" -match "^(attach|jvmti|instrument)\w*\.dll$" })
            if ($attach) {
                $suspectAttach = @($attach | Where-Object { -not (Test-KnownGoodModulePath "$($_.FileName)") })
                if ($suspectAttach) {
                    $out += New-Finding -Module "Live injection" -Title "JVM instrumentation modules present in PID $($p.Pid)" -Severity "High" `
                        -Detail "attach/instrument libraries are loaded from an unexpected path, meaning something may have attached to the running JVM after it started." `
                        -Evidence @($suspectAttach | ForEach-Object { "$($_.ModuleName) - $($_.FileName)" })
                } else {
                    $agentSummary = @($knownAgentNames | Select-Object -Unique -First 2) -join ", "
                    $source = if ($agentSummary) { " after $agentSummary started it" } else { "" }
                    $out += New-Finding -Module "Live injection" -Title "Known JVM instrumentation module present in PID $($p.Pid)" -Severity "Info" `
                        -Detail "Only launcher/JRE instrumentation files were present$source. Client naming is handled by the live memory marker scan." `
                        -Evidence @($attach | ForEach-Object { "$($_.ModuleName) - $($_.FileName)" })
                }
            }
        } catch {}

        try {
            Set-Progress "Live injection: scanning PID $($p.Pid) memory for client markers"
            $memHits = @(Search-ProcessMemoryMarkers -ProcessId $p.Pid -Signatures $CheatSignatures -MinMarkers 2 -MaxBytes 256MB)
            if ($memHits) {
                foreach ($hit in @($memHits | Select-Object -First 8)) {
                    $out += New-Finding -Module "Live injection" -Title "$($hit.Client) detected in live Java PID $($p.Pid)" -Severity "Critical" `
                        -Detail "The running JVM memory contains $($hit.MarkerCount) string(s) tied to this client. Confidence: $($hit.Confidence). This catches injected clients that are not sitting in the selected mod folder." `
                        -Evidence @($hit.Markers | ForEach-Object { "memory marker: $_" })
                }
            }
        } catch {
            $out += New-Finding -Module "Live injection" -Title "Could not scan Java memory for PID $($p.Pid)" -Severity "Low" `
                -Detail $_.Exception.Message
        }
    }

    # Live
    $perf = "$env:TEMP\hsperfdata_$env:USERNAME"
    if (Test-Path $perf) {
        $stale = @(Get-ChildItem -LiteralPath $perf -File -ErrorAction SilentlyContinue |
            Where-Object { -not (Get-Process -Id ([int]$_.Name) -ErrorAction SilentlyContinue) })
        if ($stale) {
            $out += New-Finding -Module "Live injection" -Title "Leftover JVM performance files from closed Java processes" -Severity "Low" `
                -Detail "A Java process ran and is no longer running. Not proof of anything on its own, but it dates when Java last started." `
                -Evidence @($stale | ForEach-Object { "PID $($_.Name) - started $($_.CreationTime)" })
        }
    }
    return $out
}

# Cheats
function Invoke-ProcessScan {
    $out = @()
    $procs = @()
    try { $procs = @(Get-CimInstance Win32_Process -ErrorAction Stop) }
    catch { throw "process list unavailable: $($_.Exception.Message)" }

    $byPid = @{}
    foreach ($p in $procs) { $byPid[[int]$p.ProcessId] = $p }

    $jarProcs = @()
    foreach ($p in $procs) {
        $cl = "$($p.CommandLine)"; $name = "$($p.Name)"; $path = "$($p.ExecutablePath)"

        if ($cl -match "\.jar(\b|""|'|\s)") {
            $jars = @([regex]::Matches($cl, '[^\s"'']+\.jar') | ForEach-Object { $_.Value } | Select-Object -Unique)
            $jarProcs += "PID $($p.ProcessId) $name -> $($jars -join ', ')"
            # Cheats
            if ($name -notmatch "^(javaw?|java)\.exe$") {
                $out += New-Finding -Module "Processes" -Title "Non-Java process running a .jar: $name" -Severity "High" `
                    -Detail "A .jar passed to a process that is not a Java host is a way to hide what is being loaded." `
                    -Evidence @("PID $($p.ProcessId) $path", $cl)
            }
        }

        # UI
        if ($name -match "^(svchost|csrss|lsass|winlogon|services|smss|dwm|explorer|conhost|taskhostw|RuntimeBroker)\.exe$" -and $path) {
            if ($path -notmatch "(?i)^C:\\Windows\\(System32|SysWOW64|WinSxS)\\" -and $path -notmatch "(?i)^C:\\Windows\\explorer\.exe$") {
                $out += New-Finding -Module "Processes" -Title "System process name running from the wrong folder: $name" -Severity "Critical" `
                    -Detail "A process is using a Windows system binary's name from a path Windows never uses. This is deliberate disguise." `
                    -Evidence @("PID $($p.ProcessId) $path", $cl)
            }
        }

        if ($path -and (Test-SuspectPath $path) -and $name -notmatch "^(REVS|powershell|pwsh)" ) {
            $sig = Get-SignatureInfo $path
            if ($sig.Status -ne "valid") {
                $out += New-Finding -Module "Processes" -Title "Unsigned program running from a user folder: $name" -Severity "Medium" `
                    -Detail "Signature: $($sig.Status). Installers and games normally run from Program Files and are signed; cheat loaders normally are not." `
                    -Evidence @("PID $($p.ProcessId) $path")
            }
        }

        if ($path -and $path -match "(?i)\\\`$Recycle\.Bin\\") {
            $out += New-Finding -Module "Processes" -Title "Process running from the Recycle Bin: $name" -Severity "Critical" `
                -Detail "Nothing legitimate executes from the Recycle Bin. This is a standard hiding place." `
                -Evidence @("PID $($p.ProcessId) $path")
        }

        if ($path -and -not (Test-Path -LiteralPath $path)) {
            $out += New-Finding -Module "Processes" -Title "Running process whose file was deleted: $name" -Severity "High" `
                -Detail "The program is still running but its file is gone from disk. Deleting the executable mid-check does not remove the running process." `
                -Evidence @("PID $($p.ProcessId) $path")
        }
    }

    # Live
    # Cheats
    foreach ($p in $procs) {
        if ("$($p.Name)" -notmatch "^javaw?\.exe$") { continue }
        $parent = $byPid[[int]$p.ParentProcessId]
        if (-not $parent) { continue }
        $pp = "$($parent.ExecutablePath)"
        if ($pp -and (Test-SuspectPath $pp)) {
            $sig = Get-SignatureInfo $pp
            if ($sig.Status -ne "valid") {
                $out += New-Finding -Module "Processes" -Title "Minecraft was started by an unsigned program" -Severity "High" `
                    -Detail "javaw was launched by $($parent.Name) from a user folder, signature $($sig.Status). Official launchers are signed and installed under Program Files or AppData\Local\Programs." `
                    -Evidence @("parent PID $($parent.ProcessId): $pp", "child PID $($p.ProcessId)")
            }
        }
    }

    if ($jarProcs) {
        $out += New-Finding -Module "Processes" -Title "$($jarProcs.Count) process(es) running a .jar" -Severity "Info" -Evidence $jarProcs
    }
    $out += New-Finding -Module "Processes" -Title "$($procs.Count) processes captured" -Severity "Info"
    return $out
}

# Live
function Invoke-ModuleIntegrityScan {
    $out = @()
    $flagged = @()
    $missing = @()
    $checked = 0
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        $mods = $null
        try { $mods = @($proc.Modules) } catch { continue }
        $checked++
        foreach ($m in $mods) {
            $mp = "$($m.FileName)"
            if (-not $mp -or (Test-KnownGoodModulePath $mp)) { continue }
            if (-not (Test-Path -LiteralPath $mp)) {
                $missing += "$($proc.ProcessName) (PID $($proc.Id)) <- $mp"
                continue
            }
            if (-not (Test-SuspectPath $mp)) { continue }
            $sig = Get-SignatureInfo $mp
            if ($sig.Status -ne "valid") { $flagged += "$($proc.ProcessName) (PID $($proc.Id)) <- $mp [$($sig.Status)]" }
        }
    }
    if ($missing) {
        $out += New-Finding -Module "Loaded modules" -Title "Module(s) loaded with no file on disk" -Severity "Critical" `
            -Detail "Code is mapped into a running process but the file behind it is gone. This is what a self-deleting injector leaves behind." `
            -Evidence (@($missing | Select-Object -Unique -First 25))
    }
    if ($flagged) {
        $out += New-Finding -Module "Loaded modules" -Title "$(@($flagged | Select-Object -Unique).Count) unsigned module(s) loaded from user folders" -Severity "High" `
            -Detail "Unsigned DLLs loaded out of TEMP, AppData or Downloads. Some game overlays do this legitimately, so check the names before acting." `
            -Evidence (@($flagged | Select-Object -Unique -First 25))
    }
    $out += New-Finding -Module "Loaded modules" -Title "$checked processes inspected" -Severity "Info"

    # Live
    foreach ($root in @("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows")) {
        try {
            $k = Get-ItemProperty -Path $root -ErrorAction Stop
            if ("$($k.AppInit_DLLs)".Trim()) {
                $out += New-Finding -Module "Loaded modules" -Title "AppInit_DLLs is set" -Severity "Critical" `
                    -Detail "Windows will load this DLL into nearly every process that uses user32. It is empty on a normal machine." `
                    -Evidence @("$root", "AppInit_DLLs = $($k.AppInit_DLLs)", "LoadAppInit_DLLs = $($k.LoadAppInit_DLLs)")
            }
        } catch {}
    }
    try {
        $ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        $hijacks = @(Get-ChildItem -Path $ifeo -ErrorAction Stop | ForEach-Object {
            $dbg = (Get-ItemProperty -Path $_.PSPath -Name Debugger -ErrorAction SilentlyContinue).Debugger
            if ($dbg) { "$($_.PSChildName) -> $dbg" }
        })
        if ($hijacks) {
            $out += New-Finding -Module "Loaded modules" -Title "Image File Execution Options debugger hijack" -Severity "High" `
                -Detail "Starting the named program silently starts something else instead. Used both to hijack launchers and to block detection tools." `
                -Evidence $hijacks
        }
    } catch {}
    return $out
}

# Drivers
# Cheats
function Invoke-DriverScan {
    $out = @()

    # Drivers
    try {
        $bcd = (& bcdedit /enum "{current}" 2>$null | Out-String)
        if ($bcd -match "(?im)^\s*testsigning\s+Yes") {
            $out += New-Finding -Module "Drivers" -Title "Test signing is enabled" -Severity "Critical" `
                -Detail "Windows is booted in a mode that loads unsigned kernel drivers. Cheat drivers need this unless they abuse a signed one."
        }
        if ($bcd -match "(?im)^\s*nointegritychecks\s+Yes") {
            $out += New-Finding -Module "Drivers" -Title "Driver integrity checks are disabled" -Severity "Critical" `
                -Detail "Kernel driver signature enforcement is switched off."
        }
        if ($bcd -match "(?im)^\s*debug\s+Yes") {
            $out += New-Finding -Module "Drivers" -Title "Kernel debugging is enabled" -Severity "High" `
                -Detail "A kernel debugger can read and write any process memory and is a known anti-cheat bypass."
        }
    } catch {
        $out += New-Finding -Module "Drivers" -Title "Could not read boot configuration" -Severity "Low" `
            -Detail "bcdedit failed: $($_.Exception.Message). Test signing state is unknown."
    }

    try {
        $dg = Get-CimInstance -Namespace "root\Microsoft\Windows\DeviceGuard" -ClassName Win32_DeviceGuard -ErrorAction Stop
        $out += New-Finding -Module "Drivers" -Title "Device Guard state" -Severity "Info" `
            -Evidence @("Security services running: $($dg.SecurityServicesRunning -join ', ')", "VBS status: $($dg.VirtualizationBasedSecurityStatus)")
    } catch {}

    $svcRoot = "HKLM:\SYSTEM\CurrentControlSet\Services"
    $bad = @(); $unsigned = @(); $userPath = @(); $known = @()
    try {
        foreach ($s in @(Get-ChildItem -Path $svcRoot -ErrorAction Stop)) {
            $props = $null
            try { $props = Get-ItemProperty -Path $s.PSPath -ErrorAction Stop } catch { continue }
            # Drivers
            if ($props.Type -ne 1 -and $props.Type -ne 2) { continue }
            $img = "$($props.ImagePath)"
            if (-not $img) { continue }
            $file = $img -replace '^\\\?\?\\', '' -replace '^\\SystemRoot\\', "$env:SystemRoot\" -replace '^system32\\', "$env:SystemRoot\System32\"
            if ($file -notmatch "^[A-Za-z]:\\") { $file = Join-Path $env:SystemRoot $file }
            $leaf = Split-Path -Leaf $file

            if ($VulnerableDrivers -and ($VulnerableDrivers -contains $leaf.ToLowerInvariant())) {
                $known += "$($s.PSChildName) -> $file"
            }
            if (-not (Test-Path -LiteralPath $file)) {
                # Drivers
                if ($props.Start -ne 4) { $bad += "$($s.PSChildName) -> $file (file missing, start type $($props.Start))" }
                continue
            }
            if (Test-SuspectPath $file) { $userPath += "$($s.PSChildName) -> $file" }
            $sig = Get-SignatureInfo $file
            if ($sig.Status -ne "valid") { $unsigned += "$($s.PSChildName) -> $file [$($sig.Status)]" }
        }
    } catch {
        throw "driver services unreadable: $($_.Exception.Message)"
    }

    if ($known) {
        $out += New-Finding -Module "Drivers" -Title "Known abused driver registered" -Severity "Critical" `
            -Detail "These signed drivers are on the public list of drivers cheat loaders abuse to get kernel access. Some ship with real hardware software, so confirm the vendor is actually installed." `
            -Evidence $known
    }
    if ($bad) {
        $out += New-Finding -Module "Drivers" -Title "Driver service registered but the .sys file is gone" -Severity "Critical" `
            -Detail "A driver was installed and its file deleted afterwards. Loading then deleting is exactly how a mapped cheat driver hides." `
            -Evidence (@($bad | Select-Object -First 20))
    }
    if ($userPath) {
        $out += New-Finding -Module "Drivers" -Title "Driver loaded from a user-writable folder" -Severity "High" `
            -Detail "Real drivers install under Windows\System32\drivers. A driver in TEMP, AppData or Downloads was hand-loaded." `
            -Evidence (@($userPath | Select-Object -First 20))
    }
    if ($unsigned) {
        $out += New-Finding -Module "Drivers" -Title "$($unsigned.Count) unsigned driver(s) registered" -Severity "Medium" `
            -Detail "Unsigned or untrusted driver files. Old hardware utilities can look like this, so check the names." `
            -Evidence (@($unsigned | Select-Object -First 20))
    }
    return $out
}

# Cheats
# Journal
function Invoke-ExecutionHistoryScan {
    $out = @()
    $names = @()   # Cache

    # Registry
    $bamHits = @()
    foreach ($root in @("HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings",
                        "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings")) {
        if (-not (Test-Path $root)) { continue }
        foreach ($sid in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $props = $null
            try { $props = Get-ItemProperty -Path $sid.PSPath -ErrorAction Stop } catch { continue }
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -notmatch "^\\Device\\") { continue }
                $when = $null
                try {
                    $b = [byte[]]$prop.Value
                    if ($b.Length -ge 8) { $when = [DateTime]::FromFileTime([BitConverter]::ToInt64($b, 0)) }
                } catch {}
                $bamHits += [pscustomobject]@{ Path = $prop.Name; When = $when }
                $names += (Split-Path -Leaf $prop.Name)
            }
        }
    }
    if ($bamHits.Count -eq 0) {
        $out += New-Finding -Module "Execution history" -Title "BAM holds no execution records" -Severity "High" `
            -Detail "Windows normally records every program this user has run. An empty BAM means it was cleared, or that Windows was installed or reset very recently."
    } else {
        $out += New-Finding -Module "Execution history" -Title "BAM: $($bamHits.Count) executables recorded" -Severity "Info" `
            -Evidence @($bamHits | Sort-Object When -Descending | Select-Object -First 15 |
                ForEach-Object { "$($_.When)  $($_.Path)" })
    }

    # Registry
    $pfDir = "$env:SystemRoot\Prefetch"
    $pf = @()
    if (Test-Path $pfDir) { $pf = @(Get-ChildItem -LiteralPath $pfDir -Filter *.pf -ErrorAction SilentlyContinue) }
    $prefetchOn = 3
    try {
        $prefetchOn = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name EnablePrefetcher -ErrorAction Stop).EnablePrefetcher
    } catch {}
    if ($prefetchOn -eq 0) {
        $out += New-Finding -Module "Execution history" -Title "Prefetch is switched off" -Severity "High" `
            -Detail "EnablePrefetcher is 0, so Windows stops recording which programs were started. It is on by default; turning it off is a deliberate act."
    } elseif ($pf.Count -eq 0) {
        $out += New-Finding -Module "Execution history" -Title "Prefetch folder is empty" -Severity "High" `
            -Detail "Prefetch is enabled but holds no records. The folder was emptied."
    } elseif ($pf.Count -lt 20) {
        $out += New-Finding -Module "Execution history" -Title "Only $($pf.Count) prefetch records exist" -Severity "Medium" `
            -Detail "A used Windows install normally holds well over a hundred. This few suggests the folder was cleared or Windows is brand new."
    } else {
        $out += New-Finding -Module "Execution history" -Title "Prefetch: $($pf.Count) records" -Severity "Info" `
            -Evidence @($pf | Sort-Object LastWriteTime -Descending | Select-Object -First 15 |
                ForEach-Object { "$($_.LastWriteTime)  $($_.Name)" })
        $names += @($pf | ForEach-Object { ($_.BaseName -split "-")[0] })
    }

    # Registry
    $caStore = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"
    if (Test-Path $caStore) {
        try {
            $props = Get-ItemProperty -Path $caStore -ErrorAction Stop
            $paths = @($props.PSObject.Properties | Where-Object { $_.Name -match "^[A-Za-z]:\\" } | ForEach-Object { $_.Name })
            if ($paths) {
                $names += @($paths | ForEach-Object { Split-Path -Leaf $_ })
                $out += New-Finding -Module "Execution history" -Title "Compatibility store: $($paths.Count) program paths" -Severity "Info" `
                    -Evidence @($paths | Select-Object -First 15)
            }
        } catch {}
    }

    # Registry
    $mui = "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    if (Test-Path $mui) {
        try {
            $props = Get-ItemProperty -Path $mui -ErrorAction Stop
            $paths = @($props.PSObject.Properties | Where-Object { $_.Name -match "^[A-Za-z]:\\" } | ForEach-Object { ($_.Name -split "\.")[0] + ".exe" })
            $names += @($paths | ForEach-Object { Split-Path -Leaf $_ })
        } catch {}
    }

    # Registry
    $ua = @()
    foreach ($guid in @(Get-ChildItem -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\UserAssist" -ErrorAction SilentlyContinue)) {
        $count = Join-Path $guid.PSPath "Count"
        if (-not (Test-Path $count)) { continue }
        try {
            $props = Get-ItemProperty -Path $count -ErrorAction Stop
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -match "^PS(Path|ParentPath|ChildName|Drive|Provider)$") { continue }
                $chars = $p.Name.ToCharArray()
                $dec = -join ($chars | ForEach-Object {
                    if ($_ -cmatch '[a-m]')      { [char]([int][char]$_ + 13) }
                    elseif ($_ -cmatch '[n-z]')  { [char]([int][char]$_ - 13) }
                    elseif ($_ -cmatch '[A-M]')  { [char]([int][char]$_ + 13) }
                    elseif ($_ -cmatch '[N-Z]')  { [char]([int][char]$_ - 13) }
                    else { $_ }
                })
                if ($dec -match "\.exe$") { $ua += $dec; $names += (Split-Path -Leaf $dec) }
            }
        } catch {}
    }
    if ($ua) {
        $out += New-Finding -Module "Execution history" -Title "UserAssist: $($ua.Count) launched programs" -Severity "Info" `
            -Evidence @($ua | Select-Object -First 15)
    }

    # Registry
    foreach ($pca in @("$env:SystemRoot\appcompat\pca\PcaAppLaunchDic.txt", "$env:SystemRoot\appcompat\pca\PcaGeneralDb0.txt")) {
        if (-not (Test-Path $pca)) { continue }
        try {
            $lines = @(Get-Content -LiteralPath $pca -ErrorAction Stop | Select-Object -First 2000)
            $names += @($lines | ForEach-Object { if ($_ -match "([^\\\|]+\.exe)") { $Matches[1] } })
            $out += New-Finding -Module "Execution history" -Title "PCA launch log: $($lines.Count) entries" -Severity "Info" `
                -Evidence @($lines | Select-Object -Last 10)
        } catch {}
    }

    # Cheats
    $names = @($names | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    $matched = @()
    foreach ($sig in @($CheatSignatures)) {
        foreach ($fileName in @($sig.Files)) {
            if (-not $fileName) { continue }
            $needle = $fileName.ToLowerInvariant()
            foreach ($n in $names) {
                if ($n -eq $needle -or $n.StartsWith(($needle -replace '\.(exe|jar|dll)$',''))) {
                    $matched += "$($sig.Name): $n"
                    break
                }
            }
        }
    }
    if ($matched) {
        $out += New-Finding -Module "Execution history" -Title "Windows remembers running a known cheat binary" -Severity "Critical" `
            -Detail "The file may be long deleted, but Windows kept the record that it ran on this account." `
            -Evidence @($matched | Select-Object -Unique)
    }
    $out += New-Finding -Module "Execution history" -Title "$($names.Count) distinct executables in Windows' run records" -Severity "Info"
    return $out
}

# Journal
function Invoke-DeletedFileScan {
    $out = @()
    $q = (& fsutil usn queryjournal C: 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $q -notmatch "(?i)Usn Journal ID") {
        $out += New-Finding -Module "Deleted files" -Title "The NTFS change journal is not active on C:" -Severity "High" `
            -Detail "Windows keeps this journal on by default. A missing or deleted journal removes the record of every recent file deletion, which is a known way to hide a cheat that was removed before the check." `
            -Evidence @(($q -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 4))
        return $out
    }

    $next = 0; $maxSize = 0; $first = 0
    if ($q -match "(?im)Next Usn\s*:\s*(0x[0-9a-f]+|\d+)")       { $next    = [Convert]::ToInt64($Matches[1].Replace("0x",""), $(if ($Matches[1] -match "^0x") { 16 } else { 10 })) }
    if ($q -match "(?im)Maximum Size\s*:\s*(0x[0-9a-f]+|\d+)")   { $maxSize = [Convert]::ToInt64($Matches[1].Replace("0x",""), $(if ($Matches[1] -match "^0x") { 16 } else { 10 })) }
    if ($q -match "(?im)First Usn\s*:\s*(0x[0-9a-f]+|\d+)")      { $first   = [Convert]::ToInt64($Matches[1].Replace("0x",""), $(if ($Matches[1] -match "^0x") { 16 } else { 10 })) }

    if ($first -eq 0 -and $next -lt 1000000) {
        $out += New-Finding -Module "Deleted files" -Title "The change journal was recreated recently" -Severity "High" `
            -Detail "First USN is zero and the journal has barely any history. Deleting and recreating the journal is the standard way to erase deletion records before a check." `
            -Evidence @("Next USN: $next", "Maximum size: $maxSize")
    }

    # Journal
    $start = $next - 60000000
    if ($start -lt 0) { $start = 0 }
    $interesting = @()
    $deleted = @()
    $lines = 0
    try {
        $reader = & fsutil usn readjournal C: startusn=$start csv 2>$null
        foreach ($line in $reader) {
            $lines++
            if ($lines -gt 600000) { break }
            if ($line -notmatch "(?i)\.(jar|exe|dll|sys|ahk|bat|ps1|zip|rar|7z)\b") { continue }
            $reason = ""
            if ($line -match "(?i)(File Delete|Delete Close|0x80000200|0x80000100)") { $reason = "deleted" }
            elseif ($line -match "(?i)(Rename Old Name|Rename New Name)")            { $reason = "renamed" }
            $name = ""
            if ($line -match '([^,"\\/:*?<>|]+\.(?:jar|exe|dll|sys|ahk|bat|ps1|zip|rar|7z))') { $name = $Matches[1] }
            if (-not $name) { continue }
            if ($reason -eq "deleted") { $deleted += $name } else { $interesting += $name }
        }
    } catch {
        $out += New-Finding -Module "Deleted files" -Title "Could not read the change journal" -Severity "Low" `
            -Detail $_.Exception.Message
        return $out
    }

    $deleted = @($deleted | Select-Object -Unique)
    $interesting = @($interesting | Select-Object -Unique)

    $cheatHits = @()
    foreach ($sig in @($CheatSignatures)) {
        foreach ($n in ($deleted + $interesting)) {
            foreach ($fileName in @($sig.Files)) {
                if (-not $fileName) { continue }
                if ($n -like "*$($fileName -replace '\.(exe|jar|dll)$','')*") { $cheatHits += "$($sig.Name): $n"; break }
            }
        }
    }
    if ($cheatHits) {
        $out += New-Finding -Module "Deleted files" -Title "A known cheat file name appears in the deletion journal" -Severity "Critical" `
            -Detail "The file is gone from disk, but NTFS recorded that it existed and was removed." `
            -Evidence @($cheatHits | Select-Object -Unique -First 20)
    }

    $jars = @($deleted | Where-Object { $_ -match "\.jar$" })
    if ($jars) {
        $out += New-Finding -Module "Deleted files" -Title "$($jars.Count) .jar file(s) deleted recently" -Severity "Medium" `
            -Detail "Mod updates delete jars too, so read the names before drawing a conclusion." `
            -Evidence @($jars | Select-Object -First 20)
    }
    $out += New-Finding -Module "Deleted files" -Title "$($deleted.Count) executable-type files deleted in the journal window" -Severity "Info" `
        -Evidence @($deleted | Select-Object -First 25)
    return $out
}

# UI
function Invoke-TamperScan {
    $out = @()

    # Tamper
    $watchServices = @(
        @{ Name = "DPS";      What = "Diagnostic Policy Service - feeds program-history records" },
        @{ Name = "SysMain";  What = "SysMain - maintains the prefetch records" },
        @{ Name = "EventLog"; What = "Windows Event Log" },
        @{ Name = "PcaSvc";   What = "Program Compatibility Assistant - logs program launches" },
        @{ Name = "DiagTrack";What = "Connected User Experiences - feeds several execution artifacts" }
    )
    foreach ($ws in $watchServices) {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($ws.Name)"
        if (-not (Test-Path $key)) {
            $out += New-Finding -Module "Anti-forensics" -Title "$($ws.Name) service registration is gone" -Severity "Critical" `
                -Detail "$($ws.What). The service key is missing entirely, which does not happen on its own."
            continue
        }
        try {
            $start = (Get-ItemProperty -Path $key -Name Start -ErrorAction Stop).Start
            if ($start -eq 4) {
                $out += New-Finding -Module "Anti-forensics" -Title "$($ws.Name) service is disabled" -Severity "High" `
                    -Detail "$($ws.What). Disabling it stops Windows recording evidence a screenshare relies on."
            }
        } catch {}
    }

    # Journal
    try {
        $la = (& fsutil behavior query disablelastaccess 2>$null | Out-String)
        if ($la -match "=\s*1") {
            $out += New-Finding -Module "Anti-forensics" -Title "NTFS last-access timestamps are disabled" -Severity "Low" `
                -Detail "This is the default on many Windows builds, so it is weak on its own. It matters alongside other cleared artifacts."
        }
    } catch {}

    # Tamper
    foreach ($pair in @(@{ Log = "Security"; Id = 1102 }, @{ Log = "System"; Id = 104 })) {
        try {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $pair.Log; Id = $pair.Id } -MaxEvents 5 -ErrorAction Stop)
            if ($ev) {
                $out += New-Finding -Module "Anti-forensics" -Title "The $($pair.Log) event log was cleared" -Severity "High" `
                    -Detail "Windows records the act of wiping a log." `
                    -Evidence @($ev | ForEach-Object { "$($_.TimeCreated) - $($_.Id) by $($_.UserId)" })
            }
        } catch {}
    }

    # Launcher
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $oldest = (Get-WinEvent -LogName System -MaxEvents 1 -Oldest -ErrorAction Stop).TimeCreated
        if ($oldest -gt $os.LastBootUpTime.AddMinutes(-5)) {
            $out += New-Finding -Module "Anti-forensics" -Title "System event log only goes back to the last boot" -Severity "Medium" `
                -Detail "No system events exist from before this boot, which is what a cleared log looks like after a restart." `
                -Evidence @("Oldest event: $oldest", "Last boot: $($os.LastBootUpTime)")
        }
        $up = (Get-Date) - $os.LastBootUpTime
        if ($up.TotalMinutes -lt 25) {
            $out += New-Finding -Module "Anti-forensics" -Title "The PC was restarted $([int]$up.TotalMinutes) minutes ago" -Severity "Medium" `
                -Detail "A restart immediately before a check clears memory-resident evidence and is the most common stalling tactic. Not proof by itself."
        }
        $installed = $os.InstallDate
        if ($installed -gt (Get-Date).AddDays(-3)) {
            $out += New-Finding -Module "Anti-forensics" -Title "Windows was installed $([int]((Get-Date) - $installed).TotalDays) day(s) ago" -Severity "Medium" `
                -Detail "A fresh install erases every artifact this tool reads. Legitimate, but it makes a clean result meaningless." `
                -Evidence @("Install date: $installed")
        }
    } catch {}

    # Tamper
    $cleaners = @("ccleaner","bleachbit","privazer","wisecare","kcleaner","bcuninstaller","everything","wiztree","secureeraser","eraser","fileshredder")
    $cleanerHits = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($cleaners -contains $p.ProcessName.ToLowerInvariant()) { $cleanerHits += "running: $($p.ProcessName) (PID $($p.Id))" }
    }
    if ($cleanerHits) {
        $out += New-Finding -Module "Anti-forensics" -Title "A cleaner tool is running right now" -Severity "High" `
            -Detail "Running a cleaner during or just before a screenshare destroys the evidence being checked." `
            -Evidence $cleanerHits
    }

    # Tamper
    try {
        $rb = @(Get-ChildItem -Path "C:\`$Recycle.Bin" -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $rb) {
            $out += New-Finding -Module "Anti-forensics" -Title "The Recycle Bin is completely empty" -Severity "Low" `
                -Detail "Common enough on its own, but it is the first thing emptied when someone deletes a client before a check."
        }
    } catch {}
    return $out
}

# UI
function Invoke-DefenderHistoryScan {
    $out = @()
    $found = $false
    try {
        $threats = @(Get-MpThreatDetection -ErrorAction Stop)
        if ($threats) {
            $found = $true
            $names = @{}
            try { foreach ($t in @(Get-MpThreat -ErrorAction Stop)) { $names[$t.ThreatID] = $t.ThreatName } } catch {}
            $ev = @($threats | Sort-Object InitialDetectionTime -Descending | Select-Object -First 20 | ForEach-Object {
                $n = $names[$_.ThreatID]; if (-not $n) { $n = "threat $($_.ThreatID)" }
                "$($_.InitialDetectionTime)  $n  <- $($_.Resources -join '; ')"
            })
            $sev = if (@($ev | Where-Object { $_ -match "(?i)(hacktool|injector|keylogger|riskware|trojan|autoit|ahk)" })) { "High" } else { "Medium" }
            $out += New-Finding -Module "Defender history" -Title "Defender has $($threats.Count) recorded detection(s)" -Severity $sev `
                -Detail "Defender names the file it acted on, which survives the file being deleted. Read the paths: a detection inside .minecraft or a loader folder is meaningful, a browser-download false positive is not." `
                -Evidence $ev
        }
    } catch {}

    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-Windows Defender/Operational"; Id = @(1116,1117) } -MaxEvents 25 -ErrorAction Stop)
        if ($ev) {
            $found = $true
            $out += New-Finding -Module "Defender history" -Title "$($ev.Count) Defender detection event(s) in the event log" -Severity "Medium" `
                -Detail "Each entry names what was detected and where." `
                -Evidence @($ev | Select-Object -First 12 | ForEach-Object {
                    $t = ($_.Message -split "`r?`n" | Where-Object { $_ -match "(?i)^(Name|Path):" }) -join " "
                    "$($_.TimeCreated)  $t"
                })
        }
    } catch {}

    # Cheats
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if (-not $mp.RealTimeProtectionEnabled) {
            $out += New-Finding -Module "Defender history" -Title "Defender real-time protection is off" -Severity "Medium" `
                -Detail "Turning it off is a normal prerequisite for running a cheat loader. A third-party antivirus also causes this."
        }
        $out += New-Finding -Module "Defender history" -Title "Defender status" -Severity "Info" `
            -Evidence @("Real-time: $($mp.RealTimeProtectionEnabled)", "Antivirus enabled: $($mp.AntivirusEnabled)", "Last full scan: $($mp.FullScanEndTime)")
    } catch {}

    # Cheats
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $ex = @($pref.ExclusionPath) + @($pref.ExclusionProcess) + @($pref.ExclusionExtension)
        $ex = @($ex | Where-Object { $_ })
        if ($ex) {
            $sev = if (@($ex | Where-Object { $_ -match "(?i)(minecraft|appdata|temp|downloads|desktop|\.jar|\.exe)" })) { "High" } else { "Low" }
            $out += New-Finding -Module "Defender history" -Title "$($ex.Count) Defender exclusion(s) configured" -Severity $sev `
                -Detail "An exclusion tells Defender to ignore a path or process. Excluding a user folder, .exe, or anything Minecraft-related is a strong sign something was meant to go unnoticed." `
                -Evidence $ex
        }
    } catch {}

    if (-not $found) {
        $out += New-Finding -Module "Defender history" -Title "No Defender detection history available" -Severity "Info" `
            -Detail "Either nothing was ever detected, a third-party antivirus is in use, or the history was cleared."
    }
    return $out
}

# Helpers
function Get-ExistingArtifactPath {
    param([string]$Path)
    $out = @()
    if (-not $Path) { return $out }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $matches = @()
    try {
        if ($expanded -match '[\*\?]') {
            $matches = @(Resolve-Path -Path $expanded -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath })
        } elseif (Test-Path -LiteralPath $expanded) {
            $matches = @($expanded)
        }
    } catch {}
    foreach ($m in @($matches | Select-Object -Unique | Select-Object -First 20)) {
        try {
            $item = Get-Item -LiteralPath $m -Force -ErrorAction Stop
            $out += "$m (last written $($item.LastWriteTime))"
        } catch {
            $out += $m
        }
    }
    return $out
}

# Input
function Invoke-MacroScan {
    $out = @()
    $running = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) { $running[$p.ProcessName.ToLowerInvariant()] = $p }

    foreach ($m in @($MacroSoftware)) {
        $hits = @()
        foreach ($proc in @($m.Processes)) {
            if (-not $proc) { continue }
            $key = ($proc -replace '\.exe$','').ToLowerInvariant()
            if ($running.ContainsKey($key)) { $hits += "running now: $proc (PID $($running[$key].Id))" }
        }
        foreach ($path in @($m.Paths)) {
            if (-not $path) { continue }
            foreach ($match in @(Get-ExistingArtifactPath $path)) { $hits += "installed: $match" }
        }
        foreach ($reg in @($m.Registry)) {
            if (-not $reg) { continue }
            if (Test-Path $reg) { $hits += "registry: $reg" }
        }
        if ($hits) {
            $sev = if (@($hits | Where-Object { $_ -match "^running now" })) { "High" } else { $m.Severity }
            if (-not $sev) { $sev = "Medium" }
            $out += New-Finding -Module "Macros & input" -Title "$($m.Name) present" -Severity $sev `
                -Detail $m.Note -Evidence $hits
        }
    }

    # Input
    $scriptHits = @()
    foreach ($dir in @("$env:USERPROFILE\Desktop","$env:USERPROFILE\Downloads","$env:USERPROFILE\Documents","$env:APPDATA","$env:LOCALAPPDATA\Temp")) {
        if (-not (Test-Path $dir)) { continue }
        $scriptHits += @(Get-ChildItem -LiteralPath $dir -Recurse -Depth 3 -Include *.ahk,*.ahk2,*.iim,*.mcr,*.jitbit,*.tmr -File -Force -ErrorAction SilentlyContinue |
            Select-Object -First 40 | ForEach-Object { "$($_.FullName)  ($($_.LastWriteTime))" })
    }
    if ($scriptHits) {
        $out += New-Finding -Module "Macros & input" -Title "$($scriptHits.Count) macro script file(s) on disk" -Severity "High" `
            -Detail "AutoHotkey and macro-recorder scripts. Read them: many are harmless, and an autoclicker script is not." `
            -Evidence @($scriptHits | Select-Object -First 20)
    }

    # Live
    # Input
    try {
        $pointers = @(Get-CimInstance Win32_PointingDevice -ErrorAction Stop | Where-Object { $_.Status -eq "OK" })
        $keyboards = @(Get-CimInstance Win32_Keyboard -ErrorAction Stop | Where-Object { $_.Status -eq "OK" })
        $out += New-Finding -Module "Macros & input" -Title "$($pointers.Count) pointing device(s), $($keyboards.Count) keyboard(s) attached" -Severity "Info" `
            -Evidence @(@($pointers | ForEach-Object { "mouse: $($_.Name) [$($_.PNPDeviceID)]" }) + @($keyboards | ForEach-Object { "keyboard: $($_.Name)" }))
    } catch {}

    $out += New-Finding -Module "Macros & input" -Title "Firmware macros cannot be seen from software" -Severity "Info" `
        -Detail "A macro stored on the mouse itself leaves nothing on the PC. That part of the check has to be done by watching the player and inspecting the hardware."
    return $out
}

# Evasion
# Cheats
function Invoke-EvasionScan {
    $out = @()

    $vmMarkers = @("vmware","virtualbox","vbox","qemu","kvm","xen","parallels","hyper-v","virtual machine","bochs","innotek")
    $vmHits = @()
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $blob = "$($cs.Manufacturer) $($cs.Model) $($bios.Manufacturer) $($bios.SerialNumber) $($bios.SMBIOSBIOSVersion)".ToLowerInvariant()
        foreach ($m in $vmMarkers) { if ($blob.Contains($m)) { $vmHits += "hardware identity: $($cs.Manufacturer) / $($cs.Model) / $($bios.SMBIOSBIOSVersion)"; break } }
    } catch {}
    foreach ($svc in @("VMTools","vmhgfs","VBoxService","VBoxGuest","vmci","vmmouse","prl_tools","qemu-ga")) {
        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc") { $vmHits += "guest service: $svc" }
    }
    if (Test-Path "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions") { $vmHits += "VirtualBox guest additions installed" }
    if (Test-Path "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools")          { $vmHits += "VMware Tools installed" }
    if ($vmHits) {
        $out += New-Finding -Module "Evasion" -Title "This looks like a virtual machine" -Severity "Critical" `
            -Detail "A screenshare run inside a VM proves nothing about the machine that was actually playing. Check the host, not the guest." `
            -Evidence @($vmHits | Select-Object -Unique)
    }

    $running = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) { $running[$p.ProcessName.ToLowerInvariant()] = $p }
    foreach ($r in @($RemoteControlSoftware)) {
        $hits = @()
        foreach ($proc in @($r.Processes)) {
            if (-not $proc) { continue }
            $key = ($proc -replace '\.exe$','').ToLowerInvariant()
            if ($running.ContainsKey($key)) { $hits += "running now: $proc (PID $($running[$key].Id))" }
        }
        foreach ($svc in @($r.Services)) {
            if ($svc -and (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc")) { $hits += "service installed: $svc" }
        }
        foreach ($path in @($r.Paths)) {
            if (-not $path) { continue }
            foreach ($match in @(Get-ExistingArtifactPath $path)) { $hits += "installed: $match" }
        }
        if ($hits) {
            $sev = if (@($hits | Where-Object { $_ -match "^running now" })) { $r.RunningSeverity } else { $r.Severity }
            if (-not $sev) { $sev = "Low" }
            $out += New-Finding -Module "Evasion" -Title "$($r.Name) present" -Severity $sev `
                -Detail "$($r.Note) Remote-control and input-sharing software lets a second PC drive this one, which defeats a screenshare." `
                -Evidence $hits
        }
    }

    # Evasion
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
        $virt = @($gpus | Where-Object { $_.Name -match "(?i)(virtual|parsec|idd|usbmmidd|spacedesk|duet)" })
        if ($virt) {
            $out += New-Finding -Module "Evasion" -Title "Virtual display adapter installed" -Severity "Medium" `
                -Detail "Virtual monitors are used by remote-streaming setups to give the remote side its own screen." `
                -Evidence @($virt | ForEach-Object { $_.Name })
        }
    } catch {}

    # Evasion
    try {
        $hotspot = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.InterfaceDescription -match "(?i)(remote ndis|rndis|usb.*(ethernet|tether)|iphone|android)" })
        if ($hotspot) {
            $out += New-Finding -Module "Evasion" -Title "Phone tethering adapter present" -Severity "Low" `
                -Detail "A tethered phone connection is often used to change IP between accounts." `
                -Evidence @($hotspot | ForEach-Object { "$($_.Name) - $($_.InterfaceDescription) - $($_.Status)" })
        }
    } catch {}
    return $out
}

# Cheats
function Invoke-CheatClientScan {
    $out = @()
    if (-not $CheatSignatures) {
        throw "the cheat signature list is empty"
    }
    if (-not ($SelectedModFolder -and (Test-Path -LiteralPath $SelectedModFolder))) {
        $out += New-Finding -Module "Cheat clients" -Title "No pasted mod folder path selected" -Severity "Info" `
            -Detail "Cheat-client jar scanning is folder-scoped now. Paste the exact mods/profile folder path first."
        return $out
    }

    $running = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $running[$p.ProcessName.ToLowerInvariant()] = $p
    }

    $runningInfo = @{}
    foreach ($key in @($running.Keys)) {
        $p = $running[$key]
        $runningInfo[$key] = "running now: $($p.ProcessName) (PID $($p.Id)) $($p.Path)"
    }

    $artifactThrottle = [Math]::Min([Math]::Max([Environment]::ProcessorCount, 2), 8)
    Set-Progress "Cheat clients: checking jar signatures in pasted folder"

    $searchDirs = @($SelectedModFolder)

    $markerMap = @{}
    foreach ($sig in @($CheatSignatures)) {
        $sigMarkers = @($sig.Markers) + @($sig.Strings)
        foreach ($m in @($sigMarkers)) {
            if (-not $m) { continue }
            if ($CheatSignatureBlacklist -contains $m) { continue }
            $markerMap[$m] = $sig.Name
        }
    }
    $markers = @($markerMap.Keys)

    $candidates = @()
    foreach ($dir in $searchDirs) {
        $candidates += @(Get-ChildItem -LiteralPath $dir -Recurse -Depth 4 -Include *.jar -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 4KB -and $_.Length -lt 40MB })
        if ($candidates.Count -gt 1500) { break }
    }
    $candidates = @($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 400)

    $throttle = [Math]::Min([Math]::Max([Environment]::ProcessorCount, 2), 8)
    Set-Progress "Cheat clients: scanning $($candidates.Count) binaries in parallel ($throttle workers)"
    $contentHits = @(Invoke-ParallelCheatContentScan -Candidates $candidates -MarkerMap $markerMap -Throttle $throttle)
    if ($contentHits) {
        $out += New-Finding -Module "Cheat clients" -Title "Cheat client code found inside $($contentHits.Count) file(s)" -Severity "Critical" `
            -Detail "These files carry at least two strings tied to a known cheat client, regardless of what the file is named." `
            -Evidence @($contentHits | Select-Object -First 20)
    }

    $scopeText = "pasted folder: $SelectedModFolder"
    $out += New-Finding -Module "Cheat clients" -Title "$($candidates.Count) jar(s) content-scanned against $($markers.Count) markers" -Severity "Info" `
        -Detail "Scanned $scopeText using $throttle parallel workers."
    if (-not $contentHits -and -not @($out | Where-Object { $_.Severity -eq "Critical" })) {
        $out += New-Finding -Module "Cheat clients" -Title "No known client signature matched" -Severity "Info" `
            -Detail "This only rules out the clients in the signature list. A private or renamed client with different strings would not match."
    }
    return $out
}

# Cheats
function Invoke-JarAnalysisScan {
    $out = @()
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    if (-not ($SelectedModFolder -and (Test-Path -LiteralPath $SelectedModFolder))) {
        $out += New-Finding -Module "Jar analysis" -Title "No pasted mod folder path selected" -Severity "Info" `
            -Detail "Jar analysis is folder-scoped now. Paste the exact mods/profile folder path first."
        return $out
    }
    $modDirs = @($SelectedModFolder)
    $looseDirs = @()

    $jars = @()
    foreach ($d in $modDirs)  { $jars += @(Get-ChildItem -LiteralPath $d -Recurse -Filter *.jar -File -Force -ErrorAction SilentlyContinue) }
    foreach ($d in $looseDirs) { $jars += @(Get-ChildItem -LiteralPath $d -Recurse -Depth 2 -Filter *.jar -File -Force -ErrorAction SilentlyContinue) }
    $jars = @($jars | Sort-Object FullName -Unique | Select-Object -First 600)

    if (-not $jars) {
        $out += New-Finding -Module "Jar analysis" -Title "No Minecraft jars found" -Severity "Info" `
            -Detail "No mod folders or loose jars exist in the usual places."
        return $out
    }

    $agents = @(); $mixins = @(); $nested = @(); $hooks = @(); $moduleHits = @()
    foreach ($j in $jars) {
        $zip = $null
        try { $zip = [System.IO.Compression.ZipFile]::OpenRead($j.FullName) } catch { continue }
        try {
            $entries = @($zip.Entries)
            $man = @($entries | Where-Object { $_.FullName -eq "META-INF/MANIFEST.MF" })[0]
            if ($man) {
                $sr = New-Object System.IO.StreamReader($man.Open())
                $text = $sr.ReadToEnd(); $sr.Close()
                $flags = @()
                if ($text -match "(?im)^(Premain-Class|Agent-Class|Launcher-Agent-Class)\s*:\s*(.+)$") { $flags += "declares a Java agent ($($Matches[2].Trim()))" }
                if ($text -match "(?im)^Can-Retransform-Classes\s*:\s*true")  { $flags += "can retransform loaded classes" }
                if ($text -match "(?im)^Can-Redefine-Classes\s*:\s*true")     { $flags += "can redefine loaded classes" }
                if ($text -match "(?im)^(TweakClass|Tweak-Class)\s*:\s*(.+)$"){ $flags += "installs a launch tweaker ($($Matches[2].Trim()))" }
                if ($flags) { $agents += "$($j.FullName)  ->  $($flags -join '; ')" }
            }
            if (@($entries | Where-Object { $_.FullName -match "(?i)mixins?.*\.json$" -or $_.FullName -match "(?i)org/spongepowered/asm" })) {
                $mixins += $j.FullName
            }
            if (@($entries | Where-Object { $_.FullName -match "\.jar$" })) { $nested += $j.FullName }
            $hookClasses = @($entries | Where-Object { $_.FullName -match "(?i)(inject|agent|transform|premain|hook|bypass|ghost|cheat|aimbot|killaura|reach|velocity|autoclick)\w*\.class$" } |
                ForEach-Object { $_.FullName } | Select-Object -First 6)
            if ($hookClasses) { $hooks += "$($j.Name)  ->  $($hookClasses -join ', ')" }

            $interesting = @()
            foreach ($entry in @($entries | Where-Object { $_.FullName -match '\.(class|json|txt|properties|cfg|toml|xml)$' } | Select-Object -First 500)) {
                $name = $entry.FullName
                foreach ($m in @($CheatGenericModuleStrings)) {
                    if (-not $m) { continue }
                    if ($name.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $interesting += $m }
                }
            }
            $interesting = @($interesting | Select-Object -Unique)
            if ($interesting.Count -ge 4) {
                $moduleHits += "$($j.Name)  ->  $($interesting.Count) cheat-module strings: $(@($interesting | Select-Object -First 10) -join ', ')"
            }
        } finally { if ($zip) { $zip.Dispose() } }
    }

    if ($agents) {
        $out += New-Finding -Module "Jar analysis" -Title "$($agents.Count) jar(s) declare a Java agent or launch tweaker" -Severity "High" `
            -Detail "An agent can rewrite game classes as they load. Forge, OptiFine and Mixin-based mods legitimately do this, so open the jar before concluding anything." `
            -Evidence @($agents | Select-Object -First 20)
    }
    if ($hooks) {
        $out += New-Finding -Module "Jar analysis" -Title "$($hooks.Count) jar(s) contain cheat-shaped class names" -Severity "Critical" `
            -Detail "Class names like killaura, aimbot or reach inside a mod jar are not ambiguous." `
            -Evidence @($hooks | Select-Object -First 20)
    }
    if ($moduleHits) {
        $out += New-Finding -Module "Jar analysis" -Title "$($moduleHits.Count) jar(s) contain clusters of cheat-module strings" -Severity "High" `
            -Detail "One word can collide with a legitimate mod. Four or more module names in the same jar is a stronger lead and should be opened manually." `
            -Evidence @($moduleHits | Select-Object -First 20)
    }
    if ($nested) {
        $out += New-Finding -Module "Jar analysis" -Title "$($nested.Count) jar(s) contain another jar inside" -Severity "Medium" `
            -Detail "Shipping a jar inside a jar hides the real payload from a quick look. Fabric mods do this legitimately." `
            -Evidence @($nested | Select-Object -First 15)
    }
    if ($mixins) {
        $out += New-Finding -Module "Jar analysis" -Title "$($mixins.Count) jar(s) use Mixin class patching" -Severity "Low" `
            -Detail "Normal for modern mods, and also how most modern clients patch the game. Listed for context." `
            -Evidence @($mixins | Select-Object -First 15)
    }
    $out += New-Finding -Module "Jar analysis" -Title "$($jars.Count) jar(s) inspected" -Severity "Info" `
        -Evidence @($jars | Select-Object -First 20 | ForEach-Object { "$($_.LastWriteTime)  $($_.FullName)" })
    return $out
}

# Registry
$ScanModules = @(
    @{ Key="inject";   Order=10;  Auto=$true; Icon=[char]0x26A1; Name="Live injection";     Desc="What is attached to the running game right now"; Fn="Invoke-LiveInjectionScan" },
    @{ Key="proc";     Order=20;  Auto=$true; Icon=[char]0x2615; Name="Running programs";   Desc="Java hosts, jars, disguised and file-less processes"; Fn="Invoke-ProcessScan" },
    @{ Key="modules";  Order=30;  Auto=$true; Icon=[char]0x25A3; Name="Loaded modules";     Desc="Unsigned and file-less DLLs inside live processes"; Fn="Invoke-ModuleIntegrityScan" },
    @{ Key="deleted";  Order=40;  Auto=$true; Icon=[char]0x2716; Name="Deleted files";      Desc="What was deleted or renamed, from the NTFS journal"; Fn="Invoke-DeletedFileScan" },
    @{ Key="drivers";  Order=50;  Auto=$true; Icon=[char]0x2699; Name="Drivers";            Desc="Unsigned, missing and known-abused kernel drivers"; Fn="Invoke-DriverScan" },
    @{ Key="clients";  Order=60;  Auto=$true; Icon=[char]0x26A0; Name="Cheat clients";      Desc="Hunt known clients by name, path and code inside files"; Fn="Invoke-CheatClientScan" },
    @{ Key="jars";     Order=70;  Auto=$true; Icon=[char]0x25A7; Name="Jar analysis";       Desc="Agents, tweakers and cheat classes inside Minecraft jars"; Fn="Invoke-JarAnalysisScan" },
    @{ Key="history";  Order=80;  Auto=$true; Icon=[char]0x2637; Name="Execution history";  Desc="Everything Windows remembers running, deleted or not"; Fn="Invoke-ExecutionHistoryScan" },
    @{ Key="tamper";   Order=90;  Auto=$true; Icon=[char]0x2620; Name="Anti-forensics";     Desc="Cleared logs, disabled services and wiped evidence"; Fn="Invoke-TamperScan" },
    @{ Key="defender"; Order=100; Auto=$true; Icon=[char]0x26E8; Name="Defender history";   Desc="What Windows Defender already caught and excluded"; Fn="Invoke-DefenderHistoryScan" },
    @{ Key="macros";   Order=110; Auto=$true; Icon=[char]0x25CF; Name="Macros & input";     Desc="Autoclickers, macro software and extra input devices"; Fn="Invoke-MacroScan" },
    @{ Key="evasion";  Order=120; Auto=$true; Icon=[char]0x25C9; Name="VM & remote control";Desc="Virtual machines and second-PC control setups"; Fn="Invoke-EvasionScan" }
)

# Modules
$workerNames = @(
    "Write-Log","Set-Status","Register-Proc","Start-AppOrScript","Start-CmdToolCommand",
    "Save-UrlToFile","Start-DownloadedTool","Get-GitHubAssetUrl",
    "Invoke-ToolDownloadAndRun","Invoke-WebToolDownload","Report-Run",
    "New-Finding","Add-FindingRow","Clear-Findings","Add-Finding","Set-Progress",
    "Get-Verdict","Show-Verdict","Get-MachineHeader","Write-CheckReport","Send-CheckReport",
    "Get-SignatureInfo","Test-SuspectPath","Search-FileMarkers","Search-ZipEntryMarkers","Search-ProcessMemoryMarkers","Invoke-ParallelCheatContentScan","Invoke-ParallelCheatArtifactScan","Get-ExistingArtifactPath","Get-JavaProcesses",
    "Test-KnownGoodModulePath","Get-KnownJavaAgentName","Get-ClientNameFromText","Invoke-ScanModule","Invoke-FullCheck","Invoke-SingleModule",
    "Invoke-LiveInjectionScan","Invoke-ProcessScan","Invoke-ModuleIntegrityScan","Invoke-DriverScan",
    "Invoke-ExecutionHistoryScan","Invoke-DeletedFileScan","Invoke-TamperScan","Invoke-DefenderHistoryScan",
    "Invoke-MacroScan","Invoke-EvasionScan","Invoke-CheatClientScan","Invoke-JarAnalysisScan",
    "Invoke-RegistryScan","Invoke-JavaJarScan","Invoke-ModInjectionScan"
)
$script:WorkerLib = ($workerNames | ForEach-Object { "function $_ {`n" + (Get-Command $_).Definition + "`n}" }) -join "`n"

# UI

$script:Rows = @()   # Cache

$groups = $ToolData | Group-Object Group
foreach ($g in $groups) {
    $hdr = New-Object System.Windows.Controls.StackPanel
    $hdr.Orientation = "Horizontal"; $hdr.Margin = "0,4,0,10"
    $ht = New-Object System.Windows.Controls.TextBlock
    $ht.Text = $g.Name; $ht.FontSize = 17; $ht.FontWeight = "SemiBold"; $ht.Foreground = "#F5F5F5"
    $hc = New-Object System.Windows.Controls.TextBlock
    $hc.Text = "$($g.Count)"; $hc.FontSize = 11; $hc.Foreground = "#9A9A9A"; $hc.VerticalAlignment = "Center"; $hc.Margin = "9,4,0,0"
    $hdr.Children.Add($ht) | Out-Null; $hdr.Children.Add($hc) | Out-Null
    $ListPanel.Children.Add($hdr) | Out-Null

    $cardPanel = New-Object System.Windows.Controls.WrapPanel
    $cardPanel.Margin = "0,0,0,18"
    $ListPanel.Children.Add($cardPanel) | Out-Null

    $rowBtns = @()
    foreach ($tool in $g.Group) {
        $t = $tool
        $action = if ($t.Disabled) {
            "Disabled"
        } else {
            switch ($t.Type) {
                "Cmd"  { "Run check" }
                "Link" { "Open site" }
                "Web"  { if ($t.URL -match "\.(zip|exe|msi)$") { "Download" } else { "Open site" } }
                default { "Download" }
            }
        }

        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $window.FindResource("ToolRow")
        $btn.Tag = $t
        $btn.IsEnabled = -not [bool]$t.Disabled
        Enable-FluentMotion $btn 1.012 0.978

        $grid = New-Object System.Windows.Controls.Grid
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(46) })) | Out-Null
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null

        $iconTile = New-Object System.Windows.Controls.Border
        $iconTile.Width = 32; $iconTile.Height = 32; $iconTile.CornerRadius = "6"; $iconTile.VerticalAlignment = "Center"; $iconTile.HorizontalAlignment = "Left"
        $iconTile.Background = $window.FindResource("BlueGrad")
        $iconGlyph = New-Object System.Windows.Controls.TextBlock
        $iconGlyph.Text = if ($t.Group -match "Program") { [char]0x25A3 }
            elseif ($t.Group -match "Cheat") { [char]0x26A0 }
            elseif ($t.Group -match "Minecraft") { [char]0x25A7 }
            elseif ($t.Group -match "Macros") { [char]0x25CF }
            elseif ($t.Group -match "Devices") { [char]0x25A4 }
            elseif ($t.Group -match "File") { [char]0x25A5 }
            elseif ($t.Group -match "Accounts") { [char]0x25C9 }
            elseif ($t.Group -match "System") { [char]0x2699 }
            elseif ($t.Group -match "Logs") { [char]0x2637 }
            elseif ($t.Group -match "Runtimes") { [char]0x25CE }
            else { [char]0x25C6 }
        $iconGlyph.FontSize = 18; $iconGlyph.Foreground = "#F5F5F5"; $iconGlyph.HorizontalAlignment = "Center"; $iconGlyph.VerticalAlignment = "Center"
        $iconTile.Child = $iconGlyph
        $grid.Children.Add($iconTile) | Out-Null

        $txt = New-Object System.Windows.Controls.StackPanel
        $txt.VerticalAlignment = "Center"
        $nb = New-Object System.Windows.Controls.TextBlock
        $nb.Text = $t.Name; $nb.FontSize = 12.2; $nb.FontWeight = "Bold"; $nb.Foreground = "#F5F5F5"; $nb.TextTrimming = "CharacterEllipsis"
        $db = New-Object System.Windows.Controls.TextBlock
        $db.Text = $t.Desc; $db.FontSize = 10.6; $db.Foreground = "#C8C8C8"; $db.Margin = "0,2,0,0"; $db.TextWrapping = "Wrap"; $db.MaxHeight = 30
        $badge = New-Object System.Windows.Controls.Border
        $badge.CornerRadius = "4"; $badge.Padding = "6,2"; $badge.Margin = "0,5,0,0"; $badge.HorizontalAlignment = "Left"
        $badge.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString("#3A3A3A")))
        $bt = New-Object System.Windows.Controls.TextBlock
        $badgeColor = if ($t.Disabled) { "#4A4A4A" } else { "#3A3A3A" }
        $textColor = if ($t.Disabled) { "#B0B0B0" } else { "#4CC9F0" }
        $badge.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($badgeColor)))
        $bt.Text = $action; $bt.FontSize = 9.5; $bt.FontWeight = "SemiBold"; $bt.Foreground = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($textColor)))
        $badge.Child = $bt
        $txt.Children.Add($nb) | Out-Null; $txt.Children.Add($db) | Out-Null; $txt.Children.Add($badge) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txt, 1)
        $grid.Children.Add($txt) | Out-Null
        $btn.Content = $grid

        $btn.Add_Click({
            $tool = $_.Source.Tag
            Set-Status ("Opening " + $tool.Name + "...") "busy"
            Start-Background {
                $tool = $Data
                Report-Run ("Launched tool: " + $tool.Name) -Detail ($tool.Group + " / " + $tool.Type + "`n" + $tool.URL + $tool.Command)
                switch ($tool.Type) {
                    "Cmd"  { Write-Log ("Running " + $tool.Name + " in its own window..."); Start-CmdToolCommand -Command $tool.Command; Set-Status ($tool.Name + " is running in its own window.") "ok" }
                    "Web"  { Invoke-WebToolDownload -tool $tool }
                    "Link" { Invoke-WebToolDownload -tool $tool }
                    default { Invoke-ToolDownloadAndRun -tool $tool }
                }
            } -Data $tool
        })

        $cardPanel.Children.Add($btn) | Out-Null
        $rowBtns += @{ Btn=$btn; Blob=($t.Name + " " + $t.Desc + " " + $t.Group).ToLower() }
    }
    $script:Rows += @{ Header=$hdr; Panel=$cardPanel; Rows=$rowBtns }
}

$script:TotalTools = $ToolData.Count

# UI

function Update-Filter {
    $q = $SearchBox.Text.Trim().ToLower()
    $SearchHint.Visibility = if ($q) { "Collapsed" } else { "Visible" }
    $shown = 0
    foreach ($section in $script:Rows) {
        $anyVisible = $false
        foreach ($r in $section.Rows) {
            $match = ($q -eq "") -or ($r.Blob.Contains($q))
            $wasVisible = $r.Btn.Visibility -eq "Visible"
            $r.Btn.Visibility = if ($match) { $anyVisible = $true; $shown++; "Visible" } else { "Collapsed" }
            if ($match -and -not $wasVisible) { Start-FluentReveal $r.Btn 0 4 }
        }
        $section.Header.Visibility = if ($anyVisible) { "Visible" } else { "Collapsed" }
        if ($section.Panel) { $section.Panel.Visibility = if ($anyVisible) { "Visible" } else { "Collapsed" } }
    }
    if ($q) { $CountBadge.Text = "$shown of $($script:TotalTools)" }
    else    { $CountBadge.Text = "$($script:TotalTools) tools" }
    if ($shown -eq 0) {
        $wasEmpty = $EmptyState.Visibility -eq "Visible"
        $EmptyText.Text = "No tools match `"$($SearchBox.Text.Trim())`"."
        $EmptyState.Visibility = "Visible"
        if (-not $wasEmpty) { Start-FluentReveal $EmptyState 0 8 }
    } else {
        $EmptyState.Visibility = "Collapsed"
    }
}

$SearchBox.Add_TextChanged({ Update-Filter })

$ReportingToggle.Add_Click({
    if (-not $WebhookUrls) {
        $script:ReportingState.Enabled = $false
        Update-ReportingUi
        return
    }
    $script:ReportingState.Enabled = [bool]$ReportingToggle.IsChecked
    Update-ReportingUi
    Set-Status (if ($script:ReportingState.Enabled) { "Reporting turned on." } else { "Reporting turned off." }) "ok"
})

# Registry

$ScanBox.Add_TextChanged({ $ScanHint.Visibility = if ($ScanBox.Text) { "Collapsed" } else { "Visible" } })
$doScan = {
    $term = $ScanBox.Text
    Start-Background { Invoke-RegistryScan -Term $Data } -Data $term
}.GetNewClosure()
$ScanBtn.Add_Click($doScan)
$ScanBox.Add_KeyDown({ if ($_.Key -eq "Return") { & $doScan } }.GetNewClosure())

# UI
$ModFolderBtn.Add_Click({ Select-ModFolder -Optional | Out-Null })
$JavaBtn.Add_Click({ Start-Background { Invoke-SingleModule -Key $Data } -Data "proc" })
$ModBtn.Add_Click({
    if (-not $script:SelectedModFolder) { Select-ModFolder -Optional | Out-Null }
    Start-Background { Invoke-SingleModule -Key $Data } -Data "jars"
})

# Live
foreach ($mod in ($ScanModules | Sort-Object Order)) {
    if ($mod.Key -eq "proc" -or $mod.Key -eq "jars") { continue }   # UI

    $btn = New-Object System.Windows.Controls.Button
    $btn.Style = $window.FindResource("ToolRow")
    $btn.Tag = $mod.Key
    Enable-FluentMotion $btn 1.015 0.975

    $grid = New-Object System.Windows.Controls.Grid
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(42) })) | Out-Null
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null

    $tile = New-Object System.Windows.Controls.Border
    $tile.Width = 32; $tile.Height = 32; $tile.CornerRadius = "6"
    $tile.HorizontalAlignment = "Left"; $tile.VerticalAlignment = "Center"
    $tile.Background = $window.FindResource("BlueGrad")
    $glyph = New-Object System.Windows.Controls.TextBlock
    $glyph.Text = [string]$mod.Icon; $glyph.FontSize = 18; $glyph.Foreground = "#FFFFFF"
    $glyph.HorizontalAlignment = "Center"; $glyph.VerticalAlignment = "Center"
    $tile.Child = $glyph
    $grid.Children.Add($tile) | Out-Null

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = "Center"
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = $mod.Name; $title.FontSize = 12.5; $title.FontWeight = "Bold"; $title.Foreground = "#F5F5F5"
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $mod.Desc; $desc.FontSize = 11; $desc.Foreground = "#C8C8C8"
    $desc.TextWrapping = "Wrap"; $desc.Margin = "0,3,0,0"; $desc.MaxHeight = 30
    $tagline = New-Object System.Windows.Controls.TextBlock
    $tagline.Text = "Built-in"; $tagline.FontSize = 10; $tagline.FontWeight = "SemiBold"
    $tagline.Foreground = $window.FindResource("Blue"); $tagline.Margin = "0,6,0,0"
    $stack.Children.Add($title) | Out-Null
    $stack.Children.Add($desc) | Out-Null
    $stack.Children.Add($tagline) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    $grid.Children.Add($stack) | Out-Null
    $btn.Content = $grid

    $btn.Add_Click({
        if ($_.Source.Tag -in @("clients","jars") -and -not $script:SelectedModFolder) {
            Select-ModFolder -Optional | Out-Null
        }
        Start-Background { Invoke-SingleModule -Key $Data } -Data $_.Source.Tag
    })

    $ScanCardPanel.Children.Add($btn) | Out-Null
}

$FullBtn.Add_Click({
    if (-not $script:SelectedModFolder) { Select-ModFolder -Optional | Out-Null }
    Start-Background { Invoke-FullCheck }
})
$ReportBtn.Add_Click({
    $path = $ReportBtn.Tag
    if ($path -and (Test-Path -LiteralPath $path)) { Start-Process notepad.exe "`"$path`"" }
    else { Set-Status "The report file is not there any more." "err" }
})

# UI

$TitleBar.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
$MinBtn.Add_Click({ $window.WindowState = "Minimized" })
$CloseBtn.Add_Click({ $window.Close() })

# Live
$window.Add_Closing({
    foreach ($procId in @($script:LaunchedPids)) {
        try { Start-Process taskkill -ArgumentList "/PID", $procId, "/T", "/F" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue } catch {}
    }
    if (Test-Path $installDir) {
        try { Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
})

# UI
$window.Add_Loaded({
    Start-FluentReveal $MainShell 0 10
})

Update-Filter
Show-Page "scan"
Update-ReportingUi
Start-Background { Report-Run "REVS SS TOOL started" }
$window.ShowDialog() | Out-Null
