output "vm_ips" {
  description = "Static IP of each VM"
  value       = { for name, vm in local.vms : name => "${var.net_prefix}.${vm.id}" }
}

output "ssh_commands" {
  value = { for name, vm in local.vms : name => "ssh ubuntu@${var.net_prefix}.${vm.id}" }
}
