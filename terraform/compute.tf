resource "azurerm_linux_virtual_machine" "this" {
  name                  = "uptime-kuma-vm"
  location              = local.location
  resource_group_name   = data.azurerm_resource_group.rg.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = local.tags

  admin_ssh_key {
    username = var.admin_username
    # pathexpand handles a leading ~ in the key path.
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Ubuntu 22.04 LTS, gen2. The legacy "UbuntuServer" offer tops out at 18.04.
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # cloud-init: installs k3s + ArgoCD + the app Application on first boot.
  # The bootstrap script is passed in whole so Terraform does not touch its $ syntax.
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    vm_public_ip          = azurerm_public_ip.this.ip_address
    k8s_namespace         = var.k8s_namespace
    argocd_version        = var.argocd_version
    argocd_admin_password = var.argocd_admin_password
    repo_url              = "https://github.com/noops-studio/jb-final-project.git"
    target_revision       = "main"
    chart_path            = "k8s"
    bootstrap_script      = file("${path.module}/scripts/bootstrap.sh")
  }))
}
