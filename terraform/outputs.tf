output "vm_ip" {
  value       = local.resolved_ip
  description = "IPv4 of the VM (auto-discovered from Multipass unless var.vm_ip overrides)."
}

output "vm_name" {
  value       = var.vm_name
  description = "Multipass instance name (also used as ansible hostname)."
}

output "ansible_inventory_path" {
  value       = local_file.ansible_inventory.filename
  description = "Path to the generated Ansible inventory."
}

output "next_step" {
  value = var.run_bootstrap ? "Bootstrap triggered — watch ansible output above." : "Inventory generated at IP ${local.resolved_ip}. Run: terraform apply -var=run_bootstrap=true"
}
