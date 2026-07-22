terraform {
  required_version = ">= 1.9"

  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      # Loose constraint on purpose: a module should not over-pin. The consuming
      # root is where you pin an exact version and configure the provider/backend.
      version = ">= 2.43"
    }
  }
}
