# AWS Backend Configuration
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  
  backend "s3" {
    bucket         = "terraform-state-aws-aom"
    key            = "aws/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-aws"
    
    # Use workspaces for different environments
    workspace_key_prefix = "env"
  }
}

# Generate random suffix for unique bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Configure AWS Provider
provider "aws" {
  region = "ap-southeast-1"  # Using specific region from main.tf
  
  default_tags {
    tags = local.common_tags
  }
}

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "terraform-aws"
}

# Local values for consistent tagging
locals {
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    CreatedBy     = "GitHub-Actions"
    CloudProvider = "AWS"
    LastUpdated   = timestamp()
  }
}

# Create S3 bucket for Terraform state (Bootstrap resource)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-aws-${random_id.bucket_suffix.hex}"
  
  tags = merge(local.common_tags, {
    Name        = "Terraform State Bucket"
    Description = "S3 bucket for storing Terraform state files"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "terraform-state-lock-aws"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name        = "Terraform State Lock Table"
    Description = "DynamoDB table for Terraform state locking"
  })
}

# Output important values
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "backend_config" {
  description = "Backend configuration for terraform init"
  value = {
    bucket         = aws_s3_bucket.terraform_state.bucket
    key            = "aws/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.terraform_state_lock.name
    encrypt        = true
  }
} 