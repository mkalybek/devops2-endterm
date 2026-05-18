variable "vm_ip" {
  type        = string
  description = "Reachable IPv4 of the Ubuntu VM hosting the single-node cluster."
  default     = "172.20.10.4"
}

variable "vm_hostname" {
  type        = string
  description = "Logical hostname used in inventories."
  default     = "node1"
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
