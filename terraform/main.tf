# The resource group ALREADY exists. We only READ it (data source), never manage it,
# so `terraform destroy` can never delete the RG or anything in it we did not create.
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

locals {
  # A variable default cannot reference a data source, so resolve location here:
  # use the explicit var if given, otherwise inherit the RG's region.
  location = coalesce(var.location, data.azurerm_resource_group.rg.location)

  tags = {
    project = "jb-final-project"
    app     = "uptime-kuma"
    managed = "terraform"
  }
}
