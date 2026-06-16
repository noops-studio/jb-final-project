# OPTIONAL: store Terraform state remotely in Azure (recommended for real teams).
# Local state is fine for this exam. To switch later:
#   1. Create a storage account + container once (see README "Remote state").
#   2. Uncomment this block and run: terraform init -migrate-state
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "tfstate-rg"
#     storage_account_name = "tfstateXXXXXXXX"
#     container_name       = "tfstate"
#     key                  = "uptime-kuma.tfstate"
#   }
# }
