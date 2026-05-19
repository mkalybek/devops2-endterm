variable "vm_ip" {
  type        = string
  description = "Optional override for the VM's IPv4. Leave empty to auto-discover from Multipass via scripts/multipass-ip.sh."
  default     = ""
}

variable "vm_name" {
  type        = string
  description = "Multipass instance name AND logical hostname used in inventories. Discovery feeds this to `multipass info`."
  default     = "node1"
}

variable "vm_hostname" {
  type        = string
  description = "Hostname recorded in inventories. Defaults to vm_name."
  default     = ""
}

variable "ssh_user" {
  type        = string
  description = "SSH user with sudo on the VM."
  default     = "root"
}

variable "run_bootstrap" {
  type        = bool
  description = "Trigger `ansible-playbook site.yml` after generating inventory. Off by default; set true on first apply."
  default     = false
}
