variable "proxmox_password" {
  description = "Proxmox root@pam password"
  type        = string
  sensitive   = true
}

variable "vm_password" {
  description = "Password for the nikhil user on the services VM"
  type        = string
  sensitive   = true
}
