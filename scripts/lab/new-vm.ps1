param([Parameter(Mandatory)][string]$Name,[int]$Cpu=4,[int]$MemGB=10)
Copy-Item C:\lab\images\noble-base.vhdx C:\lab\vms\$Name.vhdx
New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemGB*1GB) -VHDPath C:\lab\vms\$Name.vhdx -SwitchName LAN | Out-Null
Set-VM -Name $Name -ProcessorCount $Cpu -StaticMemory -AutomaticStartAction Start -AutomaticStopAction ShutDown -CheckpointType Disabled
Set-VMFirmware -VMName $Name -SecureBootTemplate MicrosoftUEFICertificateAuthority
Add-VMDvdDrive -VMName $Name -Path C:\lab\seeds\seed-$Name.iso
Start-VM -Name $Name
"started $Name"
