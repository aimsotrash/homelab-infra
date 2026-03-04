# Homelab Infrastructure

Private cloud infrastructure built using:

- Proxmox
- Terraform
- Kubernetes (k3s)
- Argo CD
- Atlantis
- GitHub Actions

## Architecture

Bare metal nodes running Proxmox act as the virtualization layer.
Terraform provisions worker VMs that automatically join a Kubernetes cluster using cloud-init.

Networking between nodes is provided by Tailscale.

## Observability

Prometheus + Grafana
node_exporter for hardware metrics

## GPU Workloads

A dedicated GPU worker node (RTX 3060) is exposed to the cluster using the NVIDIA device plugin.
