variable "subscription_id" {
  description = "Azure subscription ID (azurerm 4.x requires this explicitly)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the EXISTING resource group to deploy into. Read-only here; never created or destroyed."
  type        = string
}

variable "location" {
  description = "Azure region. Leave null to inherit the existing resource group's region."
  type        = string
  default     = null
}

variable "vm_size" {
  description = "VM size. Small cheap gen2 default. Use Standard_B2s or Standard_D2s_v5 if Bsv2 is unavailable in your region."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "admin_username" {
  description = "Admin username for SSH on the VM."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH PUBLIC key, e.g. ~/.ssh/id_ed25519.pub."
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace ArgoCD deploys the app into."
  type        = string
}

variable "admin_source_address" {
  description = "Your admin IP/CIDR (ideally a /32) allowed to reach SSH, the ArgoCD UI, and optionally the k8s API. Must NOT be 0.0.0.0/0."
  type        = string

  validation {
    condition     = length(trimspace(var.admin_source_address)) > 0 && var.admin_source_address != "0.0.0.0/0"
    error_message = "admin_source_address must be a specific IP/CIDR and cannot be 0.0.0.0/0."
  }
}

variable "enable_kube_api_6443" {
  description = "Open the k3s API (6443) to admin_source_address only. Off by default."
  type        = bool
  default     = false
}

variable "argocd_version" {
  description = "Pinned ArgoCD release to install, e.g. v2.13.3."
  type        = string
}

variable "argocd_admin_password" {
  description = "Optional: set the ArgoCD admin password during bootstrap. Empty keeps the generated initial password."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_from_anywhere" {
  description = "TEST ONLY: open SSH (22) to the whole internet (0.0.0.0/0) instead of admin_source_address. ArgoCD UI and the k8s API stay locked to admin_source_address. Default off."
  type        = bool
  default     = false
}

variable "enable_password_auth" {
  description = "Debug convenience: also enable SSH password login and write a LOCAL plaintext credentials file (terraform/vm-credentials.txt, gitignored). Less secure than key-only; SSH stays NSG-restricted to admin_source_address. Default off."
  type        = bool
  default     = false
}
