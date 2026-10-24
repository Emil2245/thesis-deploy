New-Item -ItemType Directory -Force C:\lab,C:\lab\images,C:\lab\vms,C:\lab\seeds | Out-Null
$a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -Command "if (-not (Get-VMSwitch -Name LAN -EA SilentlyContinue)) { New-VMSwitch -Name LAN -NetAdapterName Ethernet -AllowManagementOS $true | Out-File C:\lab\switch.log }"'
Register-ScheduledTask -TaskName lab-switch -Action $a -User SYSTEM -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName lab-switch
"started"
