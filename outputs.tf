output "app_id" {
  description = "App Platform application ID (used for `doctl apps create-deployment` and firewall trusted-source rules)."
  value       = digitalocean_app.app.id
}

output "live_url" {
  description = "The app's live URL (custom domain if set, otherwise the assigned *.ondigitalocean.app URL)."
  value       = digitalocean_app.app.live_url
}

output "default_ingress" {
  description = "The assigned *.ondigitalocean.app ingress URL. Use it to set default_uri after the first deploy when no custom domain is configured."
  value       = digitalocean_app.app.default_ingress
}

# The db_cluster_* outputs resolve to whichever mode is active, so a consuming
# root never has to know which one it is on.

output "db_cluster_id" {
  description = "UUID of the Postgres cluster backing the app — the existing one in bring-your-own mode, the created one in dedicated mode. Needed for the manual `doctl databases connection` bootstrap step."
  value       = local.db_cluster_id
}

output "db_cluster_name" {
  description = "Name of the Postgres cluster backing the app: db_cluster_name in bring-your-own mode, <app_name>-db in dedicated mode."
  value       = local.db_cluster_name
}

output "db_cluster_host" {
  description = "Public hostname of the Postgres cluster backing the app. The app itself connects over the private network via the DATABASE_URL binding; this is for administrative connections (e.g. the one-time schema GRANT)."
  value       = local.db_cluster_host
}

output "db_cluster_created" {
  description = "True when this module created the cluster (dedicated mode) rather than attaching to an existing one. Lets a consuming root branch without duplicating the create_db_cluster input."
  value       = var.create_db_cluster
}

output "db_name" {
  description = "Name of the per-app database created on the cluster."
  value       = digitalocean_database_db.app.name
}

output "db_user" {
  description = "Name of the per-app database user created on the cluster."
  value       = digitalocean_database_user.app.name
}
