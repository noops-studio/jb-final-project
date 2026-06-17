resource "azurerm_virtual_network" "this" {
  name                = "uptime-kuma-vnet"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "this" {
  name                 = "uptime-kuma-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "this" {
  name                = "uptime-kuma-nsg"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags

  # uptime-kuma is public on port 80.
  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # SSH: admin-only by default; open to the whole internet if ssh_from_anywhere = true
  # (test VMs only — this is an internet-facing brute-force surface).
  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_from_anywhere ? "*" : var.admin_source_address
    destination_address_prefix = "*"
  }

  # ArgoCD UI (NodePort 30443): admin-only by default; open to the whole internet
  # if argocd_from_anywhere = true. HIGH RISK — ArgoCD is the cluster deploy authority;
  # rotate the admin password (var.argocd_admin_password) if you expose it.
  security_rule {
    name                       = "allow-argocd"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30443"
    source_address_prefix      = var.argocd_from_anywhere ? "*" : var.admin_source_address
    destination_address_prefix = "*"
  }
}

# Optional k3s API rule (6443), admin only, created only when enabled.
resource "azurerm_network_security_rule" "kube_api" {
  count                       = var.enable_kube_api_6443 ? 1 : 0
  name                        = "allow-kube-api-admin"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefix       = var.admin_source_address
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# Standard + Static so the IP is known at create time and can be fed into cloud-init.
resource "azurerm_public_ip" "this" {
  name                = "uptime-kuma-pip"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "this" {
  name                = "uptime-kuma-nic"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    # Binds the public IP to the NIC (no separate association resource exists).
    public_ip_address_id = azurerm_public_ip.this.id
  }
}
