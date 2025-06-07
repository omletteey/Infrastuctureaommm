# Azure Backend Configuration
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  
  backend "azurerm" {
    resource_group_name  = "myResourceGroup"
    storage_account_name = "terraformstateaom"
    container_name       = "tfstate"
    key                  = "azure/terraform.tfstate"
    
    # Use workspaces for different environments
    # Remove use_azuread_auth to allow Service Principal authentication
  }
}

# Generate random suffix for unique storage account naming
resource "random_id" "storage_suffix" {
  byte_length = 4
}

# Configure Azure Provider
# Authentication will be handled through environment variables or Azure CLI
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # storage {
    #   purge_soft_deleted_keys_on_destroy = true
    # }
  }
  
  # Azure subscription details (consider using environment variables instead)
  # subscription_id = "b912e4ca-2683-4199-9209-f36fe874d46f"
  # tenant_id       = "f596e25a-399a-4387-baae-3126b8082ca4"
  # client_id       = "619a1d4f-e512-4f63-80fc-59bb2c3c5af2"
  # client_secret   = "emm8Q~njY88li8J00-2H~zaCgSjIugxtwnJnDav2"
}

# Variables
variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "terraform-azure"
}

# Local values for consistent tagging
locals {
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    CreatedBy     = "GitHub-Actions"
    CloudProvider = "Azure"
    LastUpdated   = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Create Resource Group for Terraform state resources
resource "azurerm_resource_group" "terraform_state" {
  name     = "terraform-state-rg"
  location = var.azure_location
  
  tags = merge(local.common_tags, {
    Name        = "Terraform State Resource Group"
    Description = "Resource group for Terraform state management resources"
  })
}

# Create Storage Account for Terraform state
resource "azurerm_storage_account" "terraform_state" {
  name                     = "terraformstate${random_id.storage_suffix.hex}"
  resource_group_name      = azurerm_resource_group.terraform_state.name
  location                 = azurerm_resource_group.terraform_state.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # Locally Redundant Storage
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  
  # Enable versioning for state files
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "Terraform State Storage Account"
    Description = "Storage account for storing Terraform state files"
  })
}

# Create Storage Container for state files
resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.terraform_state.name
  container_access_type = "private"
}

# Create Key Vault for sensitive values (optional but recommended)
resource "azurerm_key_vault" "terraform_state" {
  name                = "terraform-kv-${random_id.storage_suffix.hex}"
  location            = azurerm_resource_group.terraform_state.location
  resource_group_name = azurerm_resource_group.terraform_state.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = merge(local.common_tags, {
    Name        = "Terraform Key Vault"
    Description = "Key vault for storing Terraform secrets"
  })
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create access policy for current service principal/user
resource "azurerm_key_vault_access_policy" "terraform_state" {
  key_vault_id = azurerm_key_vault.terraform_state.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Recover"
  ]
  
  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Update",
    "Purge",
    "Recover"
  ]
}

# Output important values
output "resource_group_name" {
  description = "Name of the resource group for Terraform state"
  value       = azurerm_resource_group.terraform_state.name
}

output "storage_account_name" {
  description = "Name of the storage account for Terraform state"
  value       = azurerm_storage_account.terraform_state.name
}

output "container_name" {
  description = "Name of the storage container for state files"
  value       = azurerm_storage_container.terraform_state.name
}

output "key_vault_name" {
  description = "Name of the Key Vault for secrets"
  value       = azurerm_key_vault.terraform_state.name
}

output "backend_config" {
  description = "Backend configuration for terraform init"
  value = {
    resource_group_name  = azurerm_resource_group.terraform_state.name
    storage_account_name = azurerm_storage_account.terraform_state.name
    container_name       = azurerm_storage_container.terraform_state.name
    key                  = "azure/terraform.tfstate"
  }
} 