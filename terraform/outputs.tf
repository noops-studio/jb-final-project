output "app_url" {
  description = "uptime-kuma URL (ready a few minutes AFTER apply, once cloud-init finishes)."
  value       = "http://${azurerm_public_ip.this.ip_address}/"
}

output "argocd_url" {
  description = "ArgoCD UI (admin source only, self-signed TLS)."
  value       = "https://${azurerm_public_ip.this.ip_address}:30443"
}

output "ssh_command" {
  description = "SSH into the VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
}

output "argocd_password_hint" {
  description = "Run this ON the VM to read the initial ArgoCD admin password."
  value       = "sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}

output "readiness_note" {
  description = "terraform apply success != app ready."
  value       = "Apply only creates the VM. SSH in and run: cloud-init status --wait ; sudo tail -f /var/log/k3s-bootstrap.log"
}
