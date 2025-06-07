# GCP Backend Configuration
terraform {
  backend "gcs" {
    bucket = "terraform-state-gcp-aom"
    prefix = "gcp/terraform/state"
    
    # Use workspaces for different environments
    # State files will be stored as: gcp/terraform/state/env:/terraform.tfstate
  }
}

# Provider version constraints
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
}

# Generate random suffix for unique bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Get current project information
data "google_project" "current" {}

data "google_client_config" "current" {}

# Configure Google Provider
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Variables
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "sct-intranetdb"
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "terraform-gcp"
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

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com"
  ])
  
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create GCS bucket for Terraform state
resource "google_storage_bucket" "terraform_state" {
  name     = "terraform-state-gcp-${random_id.bucket_suffix.hex}"
  location = var.gcp_region
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Enable versioning
  versioning {
    enabled = true
  }
  
  # Security settings
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Encryption
  encryption {
    default_kms_key_name = google_kms_crypto_key.terraform_state.id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key.terraform_state
  ]
}

# Create KMS keyring for encryption
resource "google_kms_key_ring" "terraform_state" {
  name     = "terraform-state-keyring"
  location = var.gcp_region
  
  depends_on = [google_project_service.required_apis]
}

# Create KMS key for bucket encryption
resource "google_kms_crypto_key" "terraform_state" {
  name     = "terraform-state-key"
  key_ring = google_kms_key_ring.terraform_state.id
  
  rotation_period = "7776000s" # 90 days
  
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# Create service account for Terraform operations
resource "google_service_account" "terraform" {
  account_id   = "terraform-service-account"
  display_name = "Terraform Service Account"
  description  = "Service account for Terraform operations"
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "terraform_permissions" {
  for_each = toset([
    "roles/storage.admin",
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin"
  ])
  
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Grant access to the KMS key
resource "google_kms_crypto_key_iam_member" "terraform_kms" {
  crypto_key_id = google_kms_crypto_key.terraform_state.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.terraform.email}"
}

# Create service account key (for local development)
resource "google_service_account_key" "terraform" {
  service_account_id = google_service_account.terraform.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Store service account key in Secret Manager
resource "google_secret_manager_secret" "terraform_sa_key" {
  secret_id = "terraform-service-account-key"
  
  replication {
    automatic = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "terraform_sa_key" {
  secret      = google_secret_manager_secret.terraform_sa_key.id
  secret_data = base64decode(google_service_account_key.terraform.private_key)
}

# Grant access to the secret
resource "google_secret_manager_secret_iam_member" "terraform_sa_key" {
  secret_id = google_secret_manager_secret.terraform_sa_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}

# Output important values
output "project_id" {
  description = "GCP Project ID"
  value       = var.gcp_project_id
}

output "bucket_name" {
  description = "Name of the GCS bucket for Terraform state"
  value       = google_storage_bucket.terraform_state.name
}

output "bucket_url" {
  description = "URL of the GCS bucket"
  value       = google_storage_bucket.terraform_state.url
}

output "service_account_email" {
  description = "Email of the Terraform service account"
  value       = google_service_account.terraform.email
}

output "kms_key_id" {
  description = "ID of the KMS key for encryption"
  value       = google_kms_crypto_key.terraform_state.id
}

output "secret_manager_secret_id" {
  description = "Secret Manager secret ID for service account key"
  value       = google_secret_manager_secret.terraform_sa_key.secret_id
}

output "backend_config" {
  description = "Backend configuration for terraform init"
  value = {
    bucket = google_storage_bucket.terraform_state.name
    prefix = "gcp/terraform/state"
  }
}

# Service account key for GitHub Actions (sensitive)
output "service_account_key" {
  description = "Service account key for authentication (sensitive)"
  value       = google_service_account_key.terraform.private_key
  sensitive   = true
} 