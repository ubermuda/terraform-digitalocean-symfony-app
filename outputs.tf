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

output "db_cluster_id" {
  description = "UUID of the shared Postgres cluster (for the manual `doctl databases firewalls`/`connection` bootstrap steps)."
  value       = data.digitalocean_database_cluster.shared.id
}

output "db_name" {
  description = "Name of the per-app database created on the shared cluster."
  value       = digitalocean_database_db.app.name
}

output "db_user" {
  description = "Name of the per-app database user created on the shared cluster."
  value       = digitalocean_database_user.app.name
}
