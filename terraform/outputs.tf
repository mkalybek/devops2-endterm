output "vm_ip" {
  value       = var.vm_ip
  description = "IPv4 of the VM (single source of truth, consumed by Ansible inventories)."
}

output "ansible_inventory_path" {
  value       = local_file.ansible_inventory.filename
  description = "Path to the generated Ansible inventory."
}

output "next_step" {
  value = var.run_bootstrap ? "Bootstrap triggered. Watch ansible output above." : "Inventory generated. Run: terraform apply -var=run_bootstrap=true"
}
