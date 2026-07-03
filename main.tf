# Existing shared managed Postgres cluster (created outside Terraform, shared
# with sibling apps). For App-Platform-provisioned clusters the `name` is the
# app-<uuid> string. This is a DATA SOURCE — Terraform only reads it and never
# creates or destroys the cluster.
data "digitalocean_database_cluster" "shared" {
  name = var.db_cluster_name
}

# Dedicated database + user for this app on the shared cluster.
#
# NOTE: the DO provider creates the db + user but CANNOT manage Postgres
# privileges/ownership, and trusted sources must be appended by hand. Do NOT add
# a `digitalocean_database_firewall` resource: it is AUTHORITATIVE and would
# replace the cluster's entire trusted-source list, cutting off the sibling apps.
# See README "Manual database bootstrap".
#
# prevent_destroy guards this app's data. `terraform destroy` (or any plan that
# would delete these) errors instead of dropping the database. To tear the data
# down intentionally, `terraform state rm` the resource first (or drop it by
# hand). prevent_destroy must be a literal — it cannot be a variable.
resource "digitalocean_database_db" "app" {
  cluster_id = data.digitalocean_database_cluster.shared.id
  name       = var.db_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_database_user" "app" {
  cluster_id = data.digitalocean_database_cluster.shared.id
  name       = var.db_user

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # ${db.DATABASE_URL} is an App Platform runtime binding from the attached
  # database component named "db" — NOT a Terraform interpolation, hence $${...}.
  # DO's binding already carries ?sslmode=require, so params are appended with &.
  database_url = "$${db.DATABASE_URL}&serverVersion=16&charset=utf8"

  default_uri = var.default_uri != "" ? var.default_uri : (
    var.custom_domain != "" ? "https://${var.custom_domain}" : ""
  )

  registry_credentials = var.registry_credentials != "" ? var.registry_credentials : null

  # App-level env: inherited by the web service and the migration job. Plain
  # values only — DATABASE_URL (a ${db.*} binding) lives on the components.
  base_env = concat(
    [
      { key = "APP_ENV", value = "prod", type = "GENERAL", scope = "RUN_TIME" },
      { key = "APP_SECRET", value = var.app_secret, type = "SECRET", scope = "RUN_TIME" },
      { key = "APP_ENCRYPTION_KEY", value = var.app_encryption_key, type = "SECRET", scope = "RUN_TIME" },
      { key = "MAILER_DSN", value = var.mailer_dsn, type = "SECRET", scope = "RUN_TIME" },
      { key = "MESSENGER_TRANSPORT_DSN", value = var.messenger_transport_dsn, type = "GENERAL", scope = "RUN_TIME" },
      { key = "APP_SHARE_DIR", value = var.app_share_dir, type = "GENERAL", scope = "RUN_TIME" },
    ],
    local.default_uri != "" ? [{ key = "DEFAULT_URI", value = local.default_uri, type = "GENERAL", scope = "RUN_TIME" }] : []
  )

  extra_env_list = [
    for k, v in var.extra_env : {
      key   = k
      value = v.value
      type  = v.type
      scope = v.scope
    }
  ]

  app_env = concat(local.base_env, local.extra_env_list)
}

resource "digitalocean_app" "app" {
  spec {
    name   = var.app_name
    region = var.region

    dynamic "domain" {
      for_each = var.custom_domain != "" ? [1] : []
      content {
        name = var.custom_domain
        type = "PRIMARY"
        zone = var.domain_zone != "" ? var.domain_zone : null
      }
    }

    dynamic "env" {
      for_each = local.app_env
      content {
        key   = env.value.key
        value = env.value.value
        type  = env.value.type
        scope = env.value.scope
      }
    }

    # ── Web service: nginx + php-fpm from the prebuilt prod image ────────────
    service {
      name               = "web"
      instance_size_slug = var.instance_size_slug
      instance_count     = var.instance_count
      http_port          = var.http_port

      image {
        registry_type        = var.registry_type
        registry             = var.registry_type == "DOCR" ? null : var.registry
        repository           = var.image_repository
        tag                  = var.image_tag
        registry_credentials = local.registry_credentials

        dynamic "deploy_on_push" {
          for_each = var.registry_type == "DOCR" ? [1] : []
          content {
            enabled = var.deploy_on_push
          }
        }
      }

      health_check {
        http_path             = var.health_check_path
        initial_delay_seconds = 30
        period_seconds        = 15
        failure_threshold     = 5
      }

      # DB connection (component-level: ${db.*} bindings resolve here).
      env {
        key   = "DATABASE_URL"
        value = local.database_url
        type  = "GENERAL"
        scope = "RUN_TIME"
      }
    }

    # ── Migration job (opt-in) ───────────────────────────────────────────────
    dynamic "job" {
      for_each = var.enable_predeploy_migrations ? [1] : []
      content {
        name               = "migrate"
        kind               = "PRE_DEPLOY"
        instance_size_slug = var.instance_size_slug
        run_command        = var.migration_command

        image {
          registry_type        = var.registry_type
          registry             = var.registry_type == "DOCR" ? null : var.registry
          repository           = var.image_repository
          tag                  = var.image_tag
          registry_credentials = local.registry_credentials
        }

        env {
          key   = "DATABASE_URL"
          value = local.database_url
          type  = "GENERAL"
          scope = "RUN_TIME"
        }
      }
    }

    # ── Attach the per-app database on the shared cluster ────────────────────
    database {
      name         = "db"
      engine       = "PG"
      production   = true
      cluster_name = data.digitalocean_database_cluster.shared.name
      db_name      = digitalocean_database_db.app.name
      db_user      = digitalocean_database_user.app.name
    }
  }
}
