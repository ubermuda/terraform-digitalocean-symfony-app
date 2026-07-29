# Example consumer root for a third party with NO existing Postgres cluster:
# the module creates a dedicated one for this app and attaches it, so the first
# `terraform apply` is self-sufficient (no `doctl databases create` beforehand).
#
# Real projects reference the module by git ref:
#
#   source = "git::https://github.com/ubermuda/terraform-digitalocean-symfony-app.git//?ref=v1.7.0"
#
# Here it uses a relative path so the example can be validated in-repo.
module "app" {
  source = "../../"

  app_name = "symfony-skeleton"

  # ── Dedicated cluster ────────────────────────────────────────────────────
  # Creates a Postgres cluster named "<app_name>-db" in `region`, running
  # `database_server_version` (18). It is billed for as long as it exists.
  #
  # Do NOT also set db_cluster_name — that names an EXISTING cluster and the
  # module rejects the combination at plan time.
  create_db_cluster = true

  # Defaults shown; all optional.
  # db_cluster_size       = "db-s-1vcpu-1gb"  # smallest managed PG plan
  # db_cluster_node_count = 1                 # no standby; backups are the recovery path
  # db_cluster_version    = ""                # "" = database_server_version
  # db_cluster_region     = ""                # "" = region (keeps app and DB colocated)

  # The trusted-source list is authoritative in this mode: the app is always
  # allowed, and anything appended by hand is removed on the next apply. Add
  # your own address to run the one-time schema GRANT, then take it back out.
  # db_cluster_trusted_ips = ["203.0.113.7"]

  # Secrets (inject via TF_VAR_* — never commit).
  registry_credentials = var.registry_credentials
  app_secret           = var.app_secret
  app_encryption_key   = var.app_encryption_key

  # First deploy: keep false. The PRE_DEPLOY job would run before the schema
  # GRANT exists and fail. Do the grant, then flip this on.
  # enable_predeploy_migrations = true
}

output "app_id" {
  value = module.app.app_id
}

output "live_url" {
  value = module.app.live_url
}

output "db_cluster_id" {
  value = module.app.db_cluster_id
}

output "db_cluster_name" {
  value = module.app.db_cluster_name
}

output "db_cluster_host" {
  value = module.app.db_cluster_host
}
