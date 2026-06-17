# ─────────────────────────────────────────────────────────────────────────────
# Debugging helpers: optional VM password + local credentials file, and an
# automatic post-launch log tail via the Azure VM agent (no SSH required).
# ─────────────────────────────────────────────────────────────────────────────

# Strong, generated VM password (never hardcoded). Only USED when
# enable_password_auth = true (see compute.tf), but always generated so the
# value is stable in state.
resource "random_password" "vm" {
  length           = 24
  special          = true
  override_special = "!@#%*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Local, gitignored, 0600 credentials file. local_sensitive_file keeps the
# password OUT of plan/apply console output. Written only when password auth is on.
resource "local_sensitive_file" "vm_credentials" {
  count    = var.enable_password_auth ? 1 : 0
  filename = "${path.module}/vm-credentials.txt"
  content  = <<-EOT
    # jb-final-project VM credentials — LOCAL ONLY. DO NOT COMMIT (repo is public; this file is gitignored).
    # SSH is NSG-restricted to ${var.admin_source_address}.
    public_ip = ${azurerm_public_ip.this.ip_address}
    username  = ${var.admin_username}
    password  = ${random_password.vm.result}

    # Connect with key:
    #   ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}
    # Connect with password (enter the password above):
    #   ssh -o PubkeyAuthentication=no ${var.admin_username}@${azurerm_public_ip.this.ip_address}
  EOT
}

# After the VM is created, poll its bootstrap log THROUGH the Azure agent
# (az vm run-command) — works even when SSH/NSG is unreachable. Prints progress
# during `terraform apply` and stops when bootstrap finishes (or after ~6 min).
resource "terraform_data" "tail_bootstrap" {
  depends_on       = [azurerm_linux_virtual_machine.this]
  triggers_replace = [azurerm_linux_virtual_machine.this.id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    on_failure  = continue
    command     = <<-EOT
      set +e
      RG="${data.azurerm_resource_group.rg.name}"
      VM="${azurerm_linux_virtual_machine.this.name}"
      echo ">> Tailing VM bootstrap via Azure agent (no SSH needed). RG=$RG VM=$VM"
      for i in $(seq 1 12); do
        OUT=$(az vm run-command invoke -g "$RG" -n "$VM" \
          --command-id RunShellScript \
          --scripts "cloud-init status 2>/dev/null; echo '----- k3s-bootstrap.log (tail) -----'; tail -n 40 /var/log/k3s-bootstrap.log 2>/dev/null" \
          --query "value[0].message" -o tsv 2>/dev/null)
        echo "===================== poll $i/12 ====================="
        echo "$OUT"
        if echo "$OUT" | grep -q "Bootstrap complete"; then
          echo ">> Bootstrap complete."
          break
        fi
        sleep 30
      done
    EOT
  }
}
