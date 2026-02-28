resource "proxmox_virtual_environment_file" "worker_cloudinit" {
  count        = var.vm_count
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "death-star"

  source_raw {
    file_name = "worker-${count.index + 1}-cloudinit.yaml"
    data      = <<-EOF
      #cloud-config
      hostname: worker-${count.index + 1}
      users:
        - name: nikhil
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZjX3Zd/+QMTfqdKFqjcM5PHCzEFIfQnE+cMNVNVyMG nikhil@blade
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
      package_update: true
      packages:
        - curl
      runcmd:
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - curl -sfL https://get.k3s.io | K3S_URL=https://192.168.100.10:6443 K3S_TOKEN=K10608fabdfe84fa76cb8c68fc2e04c07c655b9de932624fc1c85d287cdb56e3f4f::server:a162b384180657228697dca45f3b6314 sh -
    EOF
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  count     = var.vm_count
  name      = "worker-${count.index + 1}"
  node_name = "death-star"
  vm_id     = 200 + count.index
  timeout_create = 120

  
  agent {
    enabled = false
  }

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.disk_size
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.${20 + count.index}/24"
        gateway = "192.168.100.2"
      }
    }
    dns {
      servers = ["8.8.8.8"]
    }
    user_data_file_id = proxmox_virtual_environment_file.worker_cloudinit[count.index].id
  }

  operating_system {
    type = "l26"
  }
}