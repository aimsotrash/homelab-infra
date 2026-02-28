variable "proxmox_password" {
  description = "Proxmox root password"
  type        = string
  sensitive   = true
}

variable "vm_count" {
  description = "Number of worker VMs to create"
  type        = number
  default     = 1
}

variable "cores" {
  description = "Number of CPU cores per VM"
  type        = number
  default     = 4
}

variable "memory" {
  description = "RAM in MB per VM"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 40
}
