output "worker_ips" {
  value = [for i in range(var.vm_count) : "192.168.100.${20 + i}"]
}