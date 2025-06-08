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
