provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {

  # Api Management config
  api_base_path = "refunds-api"

  vaultName                = join("-", [var.core_product, var.env])
  s2sUrl                   = "http://rpe-service-auth-provider-${var.env}.service.core-compute-${var.env}.internal"
  s2s_rg_prefix            = "rpe-service-auth-provider"
  s2s_key_vault_name       = var.env == "preview" || var.env == "spreview" ? join("-", ["s2s", "aat"]) : join("-", ["s2s", var.env])
  s2s_vault_resource_group = var.env == "preview" || var.env == "spreview" ? join("-", [local.s2s_rg_prefix, "aat"]) : join("-", [local.s2s_rg_prefix, var.env])
  refunds_api_url          = join("", ["http://ccpay-refunds-api-", var.env, ".service.core-compute-", var.env, ".internal"])

  # list of the thumbprints of the SSL certificates that should be accepted by the refund status API (gateway)
  refund_status_thumbprints_in_quotes     = formatlist("&quot;%s&quot;", var.refunds_api_gateway_certificate_thumbprints)
  refund_status_thumbprints_in_quotes_str = join(",", local.refund_status_thumbprints_in_quotes)
  db_server_name                          = join("-", [var.product, var.component, "postgres-db-v15"])
}

data "azurerm_key_vault" "refunds_key_vault" {
  name                = local.vaultName
  resource_group_name = join("-", [var.core_product, var.env])
}

// Database Infra
module "ccpay-refunds-database-v15" {
  providers = {
    azurerm.postgres_network = azurerm.postgres_network
  }
  source               = "git@github.com:hmcts/terraform-module-postgresql-flexible?ref=DTSPO-30107-additional-postgres-admins"
  product              = var.product
  component            = var.component
  business_area        = "cft"
  name                 = local.db_server_name
  location             = var.location
  env                  = var.env
  pgsql_admin_username = var.postgresql_user

  # Setup Access Reader db user
  force_user_permissions_trigger = "1"

  pgsql_databases = [
    {
      name : var.database_name
    }
  ]
  pgsql_server_configuration = [
    {
      name  = "azure.extensions"
      value = "pg_stat_statements,pg_buffercache"
    }
  ]
  pgsql_sku                  = var.flexible_sku_name
  admin_user_object_id       = var.jenkins_AAD_objectId
  common_tags                = var.common_tags
  pgsql_version              = var.postgresql_flexible_sql_version
  action_group_name          = join("-", [var.db_monitor_action_group_name, local.db_server_name, var.env])
  email_address_key          = var.db_alert_email_address_key
  email_address_key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}

# Populate Vault with DB info

resource "azurerm_key_vault_secret" "POSTGRES-USER" {
  name         = join("-", [var.component, "POSTGRES-USER"])
  value        = module.ccpay-refunds-database-v15.username
  key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES-PASS" {
  name         = join("-", [var.component, "POSTGRES-PASS"])
  value        = module.ccpay-refunds-database-v15.password
  key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_HOST" {
  name         = join("-", [var.component, "POSTGRES-HOST"])
  value        = module.ccpay-refunds-database-v15.fqdn
  key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_PORT" {
  name         = join("-", [var.component, "POSTGRES-PORT"])
  value        = var.postgresql_flexible_server_port
  key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_DATABASE" {
  name         = join("-", [var.component, "POSTGRES-DATABASE"])
  value        = var.database_name
  key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}


data "azurerm_key_vault" "s2s_key_vault" {
  name                = local.s2s_key_vault_name
  resource_group_name = local.s2s_vault_resource_group
}

data "azurerm_key_vault_secret" "s2s_secret" {
  name         = "microservicekey-refunds-api"
  key_vault_id = data.azurerm_key_vault.s2s_key_vault.id
}

resource "azurerm_key_vault_secret" "refunds_s2s_secret" {
  name         = "refunds-s2s-secret"
  value        = data.azurerm_key_vault_secret.s2s_secret.value
  key_vault_id = data.azurerm_key_vault.refunds_key_vault.id
}

data "azurerm_key_vault" "refund_key_vault" {
  name                = local.vaultName
  resource_group_name = local.vaultName
}

data "azurerm_key_vault_secret" "s2s_client_secret" {
  name         = "gateway-s2s-client-secret"
  key_vault_id = data.azurerm_key_vault.refund_key_vault.id
}

data "azurerm_key_vault_secret" "s2s_client_id" {
  name         = "gateway-s2s-client-id"
  key_vault_id = data.azurerm_key_vault.refund_key_vault.id
}
