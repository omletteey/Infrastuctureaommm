# GCP Backend Configuration
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  
  backend "gcs" {
    bucket = "terraform-state-gcp-aom"
    prefix = "gcp/terraform/state"
    
    # Use workspaces for different environments
    # State files will be stored as: gcp/terraform/state/env:/terraform.tfstate
  }
}


# Get current project information
data "google_project" "current" {}

data "google_client_config" "current" {}

# Configure Google Provider
# Authentication will be handled through environment variables or service account key
provider "google" {
  project = "phrasal-aegis-376702"  # Using specific project from main.tf
  region  = "asia-southeast1"       # Using specific region from main.tf
  # credentials will be provided via GOOGLE_CREDENTIALS environment variable in CI/CD
}

provider "google-beta" {
  project = "phrasal-aegis-376702"  # Using specific project from main.tf
  region  = "asia-southeast1"       # Using specific region from main.tf
  # credentials will be provided via GOOGLE_CREDENTIALS environment variable in CI/CD
}

# Variables
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "phrasal-aegis-376702"
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "asia-southeast1"
}

variable "gcp_zone" {
  description = "GCP zone for resources"
  type        = string
  default     = "asia-southeast1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "PROD"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "terraform-gcp-aom"
}

# Local values for consistent labeling
locals {
  common_labels = {
    environment    = var.environment
    project        = var.project_name
    managed-by     = "terraform"
    created-by     = "github-actions"
    cloud-provider = "gcp"
    last-updated   = formatdate("YYYY-MM-DD", timestamp())
  }
}

