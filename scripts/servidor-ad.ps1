New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 10.7.30.4 -PrefixLength 27 -DefaultGateway 10.7.30.2
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 10.7.30.4
Rename-Computer -NewName "AAA-SRV" -Restart

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "itla.local" -DomainNetbiosName "ITLA" -InstallDns -SafeModeAdministratorPassword (ConvertTo-SecureString "Dsrm-Lab-2026!" -AsPlainText -Force) -Force

New-ADOrganizationalUnit -Name "Niveles-AAA" -Path "DC=itla,DC=local"

foreach ($n in 0,5,10) {
    New-ADGroup -Name "Nivel$n" -GroupScope Global -GroupCategory Security -Path "OU=Niveles-AAA,DC=itla,DC=local" -Description "Administradores de red con privilegio $n"
}

$pw = ConvertTo-SecureString "Lab12345!" -AsPlainText -Force

foreach ($n in 0,5,10) {
    New-ADUser -Name "user-n$n" -SamAccountName "user-n$n" -UserPrincipalName "user-n$n@itla.local" -Path "OU=Niveles-AAA,DC=itla,DC=local" -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true
    Add-ADGroupMember -Identity "Nivel$n" -Members "user-n$n"
}

Get-ADGroup -Filter 'Name -like "Nivel*"' | Select-Object Name
foreach ($n in 0,5,10) { "Nivel$n :"; Get-ADGroupMember "Nivel$n" | Select-Object -ExpandProperty SamAccountName }

