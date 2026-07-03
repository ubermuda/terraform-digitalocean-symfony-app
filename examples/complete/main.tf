# Example consumer root. Real projects reference the module by git ref:
#
#   source = "git::https://github.com/ubermuda/tf-do-symfony-app.git//?ref=v1.0.0"
#
# Here it uses a relative path so the example can be validated in-repo.
module "app" {
  source = "../../"

  app_name         = "symfony-skeleton"
  image_repository = "symfony-skeleton"

  # Per-app database on the shared cluster — give each app unique names.
  db_name = "symfony_skeleton"
  db_user = "symfony_skeleton"

  # Secrets (inject via TF_VAR_* — never commit).
  registry_credentials = var.registry_credentials
  app_secret           = var.app_secret
  app_encryption_key   = var.app_encryption_key

  # Optional custom domain:
  # custom_domain = "app.example.com"
  # domain_zone   = "example.com"

  # First deploy: keep false, do the manual DB bootstrap, then flip true.
  # enable_predeploy_migrations = true

  # Project-specific env (this is the escape hatch qualendar needs):
  # extra_env = {
  #   APP_MULTITENANT         = { value = "1" }
  #   ADMIN_EMAIL             = { value = "you@example.com" }
  #   SYMFONY_TRUSTED_PROXIES = { value = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.1" }
  # }
}

# Project-specific resources live alongside the module in the root — e.g.
# qualendar's CalDAV DNS records:
#
# resource "digitalocean_record" "caldav_srv" {
#   domain   = "qualendar.app"
#   type     = "SRV"
#   name     = "_caldavs._tcp"
#   priority = 10
#   weight   = 10
#   port     = 443
#   value    = "qualendar.app."
# }

output "app_id" {
  value = module.app.app_id
}

output "live_url" {
  value = module.app.live_url
}

output "default_ingress" {
  value = module.app.default_ingress
}

output "db_cluster_id" {
  value = module.app.db_cluster_id
}
