foreach ($n in 'k3s-lab-1','k3s-lab-2','k3s-lab-3') {
  if (Get-VM -Name $n -EA SilentlyContinue) { Stop-VM -Name $n -TurnOff -Force; Remove-VM -Name $n -Force }
  Remove-Item "C:\lab\vms\$n.vhdx" -Force -EA SilentlyContinue
}
"removed"
