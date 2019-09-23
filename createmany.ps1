#Create many VM's from a Template
#Version 1.0

#variables
$vm_count = Read-Host "How many VM's would you like to deploy?"
$template = "Template"
$customspecification = "Join Domain"
$ds = "datastore"
$folder = "VM folder"
$cluster = "cluster"
$vm_prefix = "desktop-"

#Loop
write-host "Starting Deployment"
1..$vm_count | foreach {
    $y="{0:D1}" -f + $_
    $vm_name = $vm_prefix + $y
    $esxi=get-cluster $cluster | get-vmhost -state connected | Get-Random
    write-host "Creationg of VM $vm_name start" 
    new-vm -name $vm_name -template $template -vmhost $esxi -datastore $ds -location $folder -oscustomizationspec $customspecification -runasync
}