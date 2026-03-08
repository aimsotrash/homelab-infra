terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.73.0"
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

# -------------------------------------------------------------------
# Services VM — Docker host for self-hosted apps
# VM ID 201, IP 192.168.100.21
# -------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "services" {
  name    = "services"
  node_name = "death-star"
  vm_id   = 201

  clone {
    vm_id = 9000  # ubuntu-cloud-template
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192  # 8GB
  }

  # Resize the cloned disk to 64GB (template is 4GB)
  disk {
    interface    = "scsi0"
    size         = 64
    datastore_id = "local-lvm"
  }

  # Cloud-init network config — static IP on the VM bridge
  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.21/24"
        gateway = "192.168.100.2"
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_account {
      username = "nikhil"
      password = var.vm_password

      keys = [
        # Windows Blade
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZjX3Zd/+QMTfqdKFqjcM5PHCzEFIfQnE+cMNVNVyMG nikhil@blade",
        # Arch Blade
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINZP1lAx87blPJpSk9ffRM7MwT4aRsM2s8b6NPjjbt+9 nikhil@blade-arch",
        # Death-Star
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfx9TEtA7q87x8K5XT9JVr3yYQE1CRKOqwhVY1iUh+n root@death-star",
      ]
    }

    # Cloud-init runcmd: install Docker, Tailscale, and pull compose stack
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_services.id
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  on_boot = true

  lifecycle {
    ignore_changes = [
      disk[0].size,
    ]
  }
}

# -------------------------------------------------------------------
# Cloud-init user data — bootstraps Docker + Tailscale on first boot
# -------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloud_init_services" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "death-star"

  source_raw {
    data = <<-EOF
      #cloud-config
      package_update: true
      package_upgrade: true

      packages:
        - ca-certificates
        - curl
        - gnupg
        - lsb-release
        - apt-transport-https
        - qemu-guest-agent

      runcmd:
        # Enable guest agent
        - systemctl enable --now qemu-guest-agent

        # Install Docker (official method)
        - install -m 0755 -d /etc/apt/keyrings
        - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        - chmod a+r /etc/apt/keyrings/docker.asc
        - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
        - apt-get update
        - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        - usermod -aG docker nikhil
        - systemctl enable docker

        # Install Tailscale
        - curl -fsSL https://tailscale.com/install.sh | sh
        # After boot: run `sudo tailscale up` interactively to auth

        # Create directories for all services
        - mkdir -p /opt/services
        - mkdir -p /opt/services/vaultwarden
        - mkdir -p /opt/services/filebrowser
        - mkdir -p /opt/services/homarr/{configs,data,icons}
        - mkdir -p /opt/services/immich/{upload,library,model-cache,postgres,thumbs,encoded-video,profile}
        - mkdir -p /opt/services/portainer
        - chown -R 1000:1000 /opt/services

      write_files:
        - path: /etc/sysctl.d/99-forwarding.conf
          content: |
            net.ipv4.ip_forward = 1

      final_message: "Services VM ready. Run: sudo tailscale up"
    EOF

    file_name = "cloud-init-services.yaml"
  }
}

# -------------------------------------------------------------------
# Outputs
# -------------------------------------------------------------------
output "services_vm_ip" {
  value = "192.168.100.21"
}

output "services_vm_tailscale_note" {
  value = "SSH in and run: sudo tailscale up"
}
