terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }
}

provider "proxmox" {
  endpoint = "https://100.75.176.14:8006"
  username = "root@pam"
  password = var.proxmox_password
  insecure = true

  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_password
    node {
      name    = "death-star"
      address = "100.75.176.14"
      port    = 22
    }
  }
}