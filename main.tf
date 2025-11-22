// Tags
locals {
  tags = {
    class      = var.tag_class
    instructor = var.tag_instructor
    semester   = var.tag_semester
  }
}

// -----------------------------------------------------------------------------
// Random suffix for unique names
// -----------------------------------------------------------------------------

resource "random_integer" "deployment_id_suffix" {
  min = 100
  max = 999
}

// -----------------------------------------------------------------------------
// Resource Group
// -----------------------------------------------------------------------------

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.class_name}-${var.student_name}-${var.environment}-${var.location}-${random_integer.deployment_id_suffix.result}"
  location = var.location

  tags = local.tags
}

// -----------------------------------------------------------------------------
// Virtual Network & Subnet
// -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.class_name}-${var.student_name}-${var.environment}-${var.location}-${random_integer.deployment_id_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

  tags = local.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${var.class_name}-${var.student_name}-${var.environment}-${var.location}-${random_integer.deployment_id_suffix.result}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  // Service endpoints so Storage & SQL know this subnet is allowed
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.Sql"
  ]
}

// -----------------------------------------------------------------------------
// Storage Account (inside the VNet)
// -----------------------------------------------------------------------------

resource "azurerm_storage_account" "storage" {
  name                     = "sto${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  // Turn on hierarchical namespace (Data Lake Gen2) per lab instructions
  is_hns_enabled = true

  tags = local.tags
}

// Lock down storage to the virtual network + a single example IP
resource "azurerm_storage_account_network_rules" "storage_rules" {
  storage_account_id = azurerm_storage_account.storage.id

  // Deny everything by default
  default_action = "Deny"

  // Allow only this subnet from the VNet
  virtual_network_subnet_ids = [
    azurerm_subnet.subnet.id
  ]

  // Example public IP address that can still reach the storage account
  // (Colby used 100.0.0.1 as a placeholder in class – you can update to your real IP if you want)
  ip_rules = ["100.0.0.1"]
}

// -----------------------------------------------------------------------------
// SQL Server & Database
// -----------------------------------------------------------------------------

resource "azurerm_sql_server" "sql" {
  name                         = "sql-${var.class_name}-${var.student_name}-${var.environment}-${random_integer.deployment_id_suffix.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = "Password1234!" // ok for a lab; not for real prod

  tags = local.tags
}

resource "azurerm_sql_database" "sqldb" {
  name                = "db-${var.class_name}-${var.student_name}-${var.environment}-${random_integer.deployment_id_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  server_name         = azurerm_sql_server.sql.name

  // Lab says "Basic or Standard" – pick a cheap tier
  sku_name = "Basic"

  tags = local.tags
}

// Restrict SQL access to the VNet/subnet (no open public access)
resource "azurerm_sql_virtual_network_rule" "sql_vnet_rule" {
  name                = "sql-vnet-rule"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  subnet_id           = azurerm_subnet.subnet.id
}