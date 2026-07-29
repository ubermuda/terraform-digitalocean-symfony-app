# ── Where the database lives: bring your own cluster, or create one ─────────
#
# Two mutually exclusive modes, selected by create_db_cluster:
#
#   false (default) — BRING YOUR OWN. An existing cluster named by
#                     db_cluster_name is read as a DATA SOURCE; Terraform never
#                     creates or destroys it. This is what every consumer did
#                     before the dedicated mode existed.
#   true            — DEDICATED. Terraform creates a Postgres cluster for this
#                     app alone and uses it. Costs real money; see variables.
#
# variables.tf validates that the two are not combined.
locals {
  # The cluster this module attached to before db_cluster_name had a default of
  # "". Kept as a literal so a consumer who never set db_cluster_name resolves
  # to exactly the same name as before and sees no plan diff.
  default_shared_db_cluster_name = "app-22613a04-caee-4039-ad37-76858ef7c162"

  byo_db_cluster_name = var.db_cluster_name != "" ? var.db_cluster_name : local.default_shared_db_cluster_name

  # A created cluster is named off app_name, like image_repository and db_name.
  # There is no override variable: naming a cluster you did not create is
  # precisely what db_cluster_name (bring-your-own mode) is for.
  dedicated_db_cluster_name = "${var.app_name}-db"

  # Empty means "inherit database_server_version", so DATABASE_URL's
  # serverVersion cannot over-state the engine version by drifting from it.
  # db_cluster_region deliberately does NOT inherit var.region: the two are
  # different slug namespaces (see the variable).
  dedicated_db_cluster_version = var.db_cluster_version != "" ? var.db_cluster_version : var.database_server_version

  # Whichever mode is active, resolved once. `one()` of a splat yields null for
  # the mode that is switched off (count = 0); a conditional would fail on the
  # count = 0 side because Terraform evaluates BOTH branches of `? :`.
  db_cluster_id = coalesce(
    one(digitalocean_database_cluster.dedicated[*].id),
    one(data.digitalocean_database_cluster.shared[*].id),
  )
  db_cluster_name = coalesce(
    one(digitalocean_database_cluster.dedicated[*].name),
    one(data.digitalocean_database_cluster.shared[*].name),
  )
  db_cluster_host = coalesce(
    one(digitalocean_database_cluster.dedicated[*].host),
    one(data.digitalocean_database_cluster.shared[*].host),
  )
}

# Bring-your-own: an existing managed Postgres cluster (created outside
# Terraform, typically shared with sibling apps). For App-Platform-provisioned
# clusters the `name` is the app-<uuid> string. This is a DATA SOURCE —
# Terraform only reads it and never creates or destroys the cluster.
data "digitalocean_database_cluster" "shared" {
  count = var.create_db_cluster ? 0 : 1

  name = local.byo_db_cluster_name
}

# Dedicated: a Postgres cluster for this app alone, owned by this state.
#
# prevent_destroy guards the entire application database, not just one app's
# schema — this is the resource whose accidental removal loses everything. It
# also means flipping create_db_cluster back to false ERRORS rather than
# silently destroying the cluster: `terraform state rm` first if that is really
# what you want. prevent_destroy must be a literal — it cannot be a variable.
resource "digitalocean_database_cluster" "dedicated" {
  count = var.create_db_cluster ? 1 : 0

  name       = local.dedicated_db_cluster_name
  engine     = "pg"
  version    = local.dedicated_db_cluster_version
  size       = var.db_cluster_size
  node_count = var.db_cluster_node_count
  region     = var.db_cluster_region
  tags       = var.db_cluster_tags

  lifecycle {
    prevent_destroy = true
  }
}

# App Platform and managed databases name the same physical location
# differently ("tor" vs "tor1"), so nothing stops a consumer from setting one
# and forgetting the other and quietly ending up cross-region: it works, but
# the app then reaches its database over the public internet instead of the
# private network. A `check` block warns without blocking, because putting them
# apart on purpose is legitimate.
check "db_cluster_colocated_with_app" {
  assert {
    condition     = !var.create_db_cluster || substr(var.db_cluster_region, 0, 3) == var.region
    error_message = "db_cluster_region (${var.db_cluster_region}) is not in the same metro as region (${var.region}), so the app will not reach its database over the private network. Set db_cluster_region to a datacenter in ${var.region} (e.g. ${var.region}1) unless you mean to split them."
  }
}

# Trusted sources for a cluster this module owns. `digitalocean_database_firewall`
# is AUTHORITATIVE — it replaces the cluster's whole trusted-source list — which
# is why it must never be used against a SHARED cluster (it would cut off the
# sibling apps) and is created only in dedicated mode. Here that authority is
# what you want: the cluster reaches a known, declared state instead of whatever
# `doctl databases firewalls append` last did.
#
# ORDERING: this is created AFTER digitalocean_app, because the app's own ID is
# the rule. The app's first deployment therefore comes up before this list
# exists — the same position bring-your-own mode is in, where trusted sources
# are appended by hand once `terraform output app_id` has a value. That is why
# enable_predeploy_migrations must stay off for the first deploy in both modes.
#
# The consequence of an authoritative list is that a human needs
# db_cluster_trusted_ips to get in — see README "Database bootstrap".
resource "digitalocean_database_firewall" "dedicated" {
  count = var.create_db_cluster ? 1 : 0

  cluster_id = digitalocean_database_cluster.dedicated[0].id

  rule {
    type  = "app"
    value = digitalocean_app.app.id
  }

  dynamic "rule" {
    for_each = toset(var.db_cluster_trusted_ips)
    content {
      type  = "ip_addr"
      value = rule.value
    }
  }
}

# Dedicated database + user for this app on whichever cluster is in play.
#
# NOTE: the DO provider creates the db + user but CANNOT manage Postgres
# privileges/ownership, so the schema GRANT stays a manual step in both modes.
# See README "Database bootstrap".
#
# prevent_destroy guards this app's data. `terraform destroy` (or any plan that
# would delete these) errors instead of dropping the database. To tear the data
# down intentionally, `terraform state rm` the resource first (or drop it by
# hand). prevent_destroy must be a literal — it cannot be a variable.
resource "digitalocean_database_db" "app" {
  cluster_id = local.db_cluster_id
  name       = local.db_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_database_user" "app" {
  cluster_id = local.db_cluster_id
  name       = local.db_user

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # A new consumer only needs to set app_name — the image repo and DB
  # names default off it. All overridable via their own variables.
  image_repository = coalesce(var.image_repository, var.app_name)
  db_name          = coalesce(var.db_name, replace(var.app_name, "-", "_"))
  db_user          = coalesce(var.db_user, local.db_name)

  # ${<db-component>.DATABASE_URL} is an App Platform runtime binding from the
  # attached database component — NOT a Terraform interpolation, hence the $${...}
  # escaping around the literal binding. The component name is interpolated in.
  # DO's binding already carries ?sslmode=require, so params are appended with &.
  database_url = "$${${var.database_component_name}.DATABASE_URL}&serverVersion=${var.database_server_version}&charset=utf8"

  default_uri = var.default_uri != "" ? var.default_uri : (
    var.custom_domain != "" ? "https://${var.custom_domain}" : ""
  )

  registry_credentials = var.registry_credentials != "" ? var.registry_credentials : null

  # App-level env: inherited by every component (web service, migration job,
  # worker). Plain values only — DATABASE_URL (a ${db.*} binding) lives on
  # the components.
  base_env = concat(
    [
      { key = "APP_ENV", value = "prod", type = "GENERAL", scope = "RUN_TIME" },
      { key = "APP_SECRET", value = var.app_secret, type = "SECRET", scope = "RUN_TIME" },
      { key = "APP_ENCRYPTION_KEY", value = var.app_encryption_key, type = "SECRET", scope = "RUN_TIME" },
      { key = "MAILER_DSN", value = var.mailer_dsn, type = "SECRET", scope = "RUN_TIME" },
      { key = "MESSENGER_TRANSPORT_DSN", value = var.messenger_transport_dsn, type = "GENERAL", scope = "RUN_TIME" },
      { key = "APP_SHARE_DIR", value = var.app_share_dir, type = "GENERAL", scope = "RUN_TIME" },
    ],
    local.default_uri != "" ? [{ key = "DEFAULT_URI", value = local.default_uri, type = "GENERAL", scope = "RUN_TIME" }] : [],
    var.enable_mercure ? [
      # Publishers reach the hub over the app's private network; subscribers
      # (a developer's machine running the bridge) need the public route, so
      # both are derived here rather than left to the consuming app.
      { key = "MERCURE_URL", value = "http://${var.mercure_component_name}${var.mercure_path}", type = "GENERAL", scope = "RUN_TIME" },
      { key = "MERCURE_PUBLIC_URL", value = "${local.default_uri}${var.mercure_path}", type = "GENERAL", scope = "RUN_TIME" },
      { key = "MERCURE_JWT_SECRET", value = var.mercure_jwt_secret, type = "SECRET", scope = "RUN_TIME" },
    ] : []
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
      name               = var.service_component_name
      instance_size_slug = var.instance_size_slug
      instance_count     = var.instance_count
      http_port          = var.http_port

      image {
        registry_type        = var.registry_type
        registry             = var.registry_type == "DOCR" ? null : var.registry
        repository           = local.image_repository
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
          repository           = local.image_repository
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

    # ── Background worker (opt-in): same image, supervised by App Platform ──
    dynamic "worker" {
      for_each = var.enable_worker ? [1] : []
      content {
        name               = var.worker_component_name
        instance_size_slug = var.worker_instance_size_slug != "" ? var.worker_instance_size_slug : var.instance_size_slug
        instance_count     = var.worker_instance_count
        run_command        = var.worker_command

        image {
          registry_type        = var.registry_type
          registry             = var.registry_type == "DOCR" ? null : var.registry
          repository           = local.image_repository
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

    # ── Mercure hub (opt-in): a public image, not the app's ──────────────
    dynamic "service" {
      for_each = var.enable_mercure ? [1] : []
      content {
        name               = var.mercure_component_name
        instance_size_slug = var.mercure_instance_size_slug != "" ? var.mercure_instance_size_slug : var.instance_size_slug
        instance_count     = 1
        http_port          = 80

        image {
          registry_type = "DOCKER_HUB"
          registry      = split("/", var.mercure_image)[0]
          repository    = split("/", var.mercure_image)[1]
          tag           = var.mercure_image_tag
        }

        # The hub is stateless and in-memory: delivery is best effort, and a
        # restart drops undelivered updates. Publishers that need durability
        # keep their own outbox.
        env {
          key   = "SERVER_NAME"
          value = ":80"
          type  = "GENERAL"
          scope = "RUN_TIME"
        }
        env {
          key   = "MERCURE_PUBLISHER_JWT_KEY"
          value = var.mercure_jwt_secret
          type  = "SECRET"
          scope = "RUN_TIME"
        }
        env {
          key   = "MERCURE_SUBSCRIBER_JWT_KEY"
          value = var.mercure_jwt_secret
          type  = "SECRET"
          scope = "RUN_TIME"
        }

        dynamic "env" {
          for_each = var.mercure_extra_directives != "" ? [1] : []
          content {
            key   = "MERCURE_EXTRA_DIRECTIVES"
            value = var.mercure_extra_directives
            type  = "GENERAL"
            scope = "RUN_TIME"
          }
        }
      }
    }

    # Route all traffic to the web service. Set explicitly (rather than relying
    # on App Platform's implicit default) so that migrating an app which already
    # has an ingress rule rewrites it to this component — otherwise the provider
    # keeps the app's prior (computed) ingress, which may reference an old
    # component name and fail spec validation.
    ingress {
      # Listed first: App Platform evaluates rules in order, so the hub's
      # specific path must precede the web service's "/" catch-all or every
      # request reaches the app instead.
      dynamic "rule" {
        for_each = var.enable_mercure ? [1] : []
        content {
          component {
            name = var.mercure_component_name
          }
          match {
            path {
              prefix = var.mercure_path
            }
          }
        }
      }

      rule {
        component {
          name = var.service_component_name
        }
        match {
          path {
            prefix = "/"
          }
        }
      }
    }

    # ── Attach the per-app database on the cluster in play ───────────────────
    # Same shape either way: App Platform attaches an existing cluster by name,
    # and by the time this evaluates the dedicated cluster (if any) exists.
    database {
      name         = var.database_component_name
      engine       = "PG"
      production   = true
      cluster_name = local.db_cluster_name
      db_name      = digitalocean_database_db.app.name
      db_user      = digitalocean_database_user.app.name
    }
  }
}
