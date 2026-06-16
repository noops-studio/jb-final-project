# azurerm 4.x requires an explicit subscription id (via this var or ARM_SUBSCRIPTION_ID).
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
