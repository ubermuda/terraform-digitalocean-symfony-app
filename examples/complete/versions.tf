terraform {
  required_version = ">= 1.5"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.43"
    }
  }

  # Real projects: use an encrypted remote backend — state holds SECRET env
  # plaintext. Example (DigitalOcean Spaces):
  #
  # backend "s3" {
  #   endpoints                   = { s3 = "https://<region>.digitaloceanspaces.com" }
  #   bucket                      = "my-tfstate"
  #   key                         = "<app>/terraform.tfstate"
  #   region                      = "us-east-1"
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  # }
}

# Provider config lives in the ROOT, never in the module.
provider "digitalocean" {
  token = var.do_token
}

variable "do_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "DigitalOcean API token. Leave null to read DIGITALOCEAN_TOKEN from the environment."
}

variable "registry_credentials" {
  type      = string
  default   = ""
  sensitive = true
}

variable "app_secret" {
  type      = string
  sensitive = true
}

variable "app_encryption_key" {
  type      = string
  sensitive = true
}
