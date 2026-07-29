# ---------------------------------------------------------------------------
# Identity & placement
# ---------------------------------------------------------------------------

variable "app_name" {
  type        = string
  description = "App Platform application name. Also the default for image_repository, db_name (hyphens->underscores), and db_user — so for a new app this is often the only identifier you set."
}

variable "region" {
  type        = string
  description = "App Platform region slug. MUST match the database cluster's region so traffic stays on the private network: with create_db_cluster the cluster is created here (unless db_cluster_region overrides it); otherwise this must match the existing cluster you point db_cluster_name at (the default shared cluster lives in tor)."
  default     = "tor"
}

# ---------------------------------------------------------------------------
# Container image (prebuilt & pushed by the consumer, e.g. `just build-prod`)
# ---------------------------------------------------------------------------

variable "registry_type" {
  type        = string
  description = "Image registry type: GHCR, DOCR (DigitalOcean Container Registry), or DOCKER_HUB."
  default     = "GHCR"

  validation {
    condition     = contains(["GHCR", "DOCR", "DOCKER_HUB"], var.registry_type)
    error_message = "registry_type must be GHCR, DOCR, or DOCKER_HUB."
  }
}

variable "registry" {
  type        = string
  description = "Registry namespace. For GHCR/Docker Hub this is your org/user (e.g. ubermuda). Leave empty for DOCR."
  default     = "ubermuda"
}

variable "image_repository" {
  type        = string
  default     = null
  description = "Image repository name within the registry. Defaults to app_name."
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy."
  default     = "prod"
}

variable "registry_credentials" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Pull credential for a private registry, in the form DO expects (e.g. \"username:PAT\" for GHCR with a read:packages token). Required for GHCR/private Docker Hub; leave empty for DOCR."
}

variable "deploy_on_push" {
  type        = bool
  description = "Auto-deploy when a new image is pushed (DOCR only; ignored for GHCR/Docker Hub)."
  default     = true
}

# ---------------------------------------------------------------------------
# Instance sizing
# ---------------------------------------------------------------------------

variable "instance_size_slug" {
  type        = string
  description = "App Platform instance size slug for the web service (and, when enabled, the migration job and the worker unless worker_instance_size_slug overrides it)."
  default     = "apps-s-1vcpu-0.5gb"
}

variable "instance_count" {
  type        = number
  description = "Number of web service instances."
  default     = 1
}

variable "http_port" {
  type        = number
  description = "Port the container listens on (nginx in docker/prod listens on 80)."
  default     = 80
}

variable "health_check_path" {
  type        = string
  description = "HTTP path App Platform pings for health checks. Defaults to /login: public (PUBLIC_ACCESS) and returns 200, whereas / is behind ROLE_USER and 302-redirects."
  default     = "/login"
}

# ---------------------------------------------------------------------------
# Database: bring your own cluster (default), or create a dedicated one
#
# Exactly one of the two. create_db_cluster = false (the default) reads an
# existing cluster named by db_cluster_name; create_db_cluster = true makes the
# module create a Postgres cluster for this app alone. Setting both is a
# configuration error, caught by the validation on db_cluster_name below.
# ---------------------------------------------------------------------------

variable "create_db_cluster" {
  type        = bool
  default     = false
  description = "Create a DEDICATED Postgres cluster for this app instead of attaching to an existing one. Off by default: existing consumers keep bringing their own cluster with no change. A dedicated cluster is billed hourly for as long as it exists — size it with db_cluster_size / db_cluster_node_count."
}

variable "db_cluster_name" {
  type        = string
  description = "Bring-your-own mode only: name of the EXISTING Postgres cluster to attach to. For App-Platform-provisioned clusters the name IS the app-<uuid> string; pass it directly (no lookup). Empty keeps the historical default shared cluster (app-22613a04-…). Must be left empty when create_db_cluster is true — the created cluster is named <app_name>-db."
  default     = ""

  validation {
    condition     = !(var.create_db_cluster && var.db_cluster_name != "")
    error_message = "db_cluster_name names an EXISTING cluster and cannot be combined with create_db_cluster = true. Either remove db_cluster_name to have the module create a dedicated cluster named \"<app_name>-db\", or drop create_db_cluster to attach to the named cluster."
  }
}

variable "db_cluster_size" {
  type        = string
  default     = "db-s-1vcpu-1gb"
  description = "Dedicated mode only: DigitalOcean database droplet size slug for the created cluster. The default is the smallest managed Postgres plan — adequate for a small app, and a deliberate floor so nobody provisions an expensive cluster by accident. `doctl databases options slugs --engine pg` lists the alternatives."
}

variable "db_cluster_node_count" {
  type        = number
  default     = 1
  description = "Dedicated mode only: number of nodes in the created cluster. 1 is a single node with no standby (a node failure is downtime, and DO's daily backups are the recovery path); 2+ adds standby nodes and multiplies the cost."
}

variable "db_cluster_version" {
  type        = string
  default     = ""
  description = "Dedicated mode only: PostgreSQL major version for the created cluster. Empty means: use database_server_version, so DATABASE_URL's serverVersion cannot over-state the engine version by drifting from it."
}

variable "db_cluster_region" {
  type        = string
  default     = "tor1"
  description = "Dedicated mode only: DATACENTER slug for the created cluster. NOT the same namespace as `region`: App Platform takes a metro slug (tor, nyc, ams) while managed databases take a numbered datacenter slug (tor1, nyc3, ams3), and passing the metro form here is rejected by the API at apply. Set it to a datacenter in the same metro as `region` so app and cluster share the private network — the default pair is tor / tor1."

  validation {
    # Catches the mistake this variable exists to make visible: passing the App
    # Platform slug ("tor") where a datacenter slug ("tor1") is required. The
    # provider does no client-side check, so without this it surfaces as an
    # opaque API error on the first apply.
    condition     = can(regex("^[a-z]{3}[0-9]+$", var.db_cluster_region))
    error_message = "db_cluster_region must be a DigitalOcean datacenter slug such as tor1, nyc3 or ams3 — not an App Platform region slug like tor. Managed databases and App Platform use different region namespaces."
  }
}

variable "db_cluster_tags" {
  type        = list(string)
  default     = []
  description = "Dedicated mode only: tags applied to the created cluster."
}

variable "db_cluster_trusted_ips" {
  type        = list(string)
  default     = []
  description = "Dedicated mode only: extra IPs or CIDRs allowed to reach the created cluster, on top of the app itself (which the module always allows). The trusted-source list is AUTHORITATIVE in this mode, so anything appended by hand is removed on the next apply — add your address here to run the one-time schema GRANT, then remove it."
}

variable "db_name" {
  type        = string
  default     = null
  description = "Per-app database created on the cluster. Defaults to app_name with hyphens turned into underscores (a valid Postgres identifier). Each app gets its own so siblings on a shared cluster don't collide."
}

variable "db_user" {
  type        = string
  default     = null
  description = "Per-app database user created on the cluster. Defaults to the database name (db_name)."
}

variable "database_server_version" {
  type        = string
  default     = "18"
  description = "PostgreSQL major version advertised to Doctrine via the DATABASE_URL serverVersion parameter. Must match the managed cluster's engine version — the default shared cluster runs PG 18, and a cluster created by this module uses this value unless db_cluster_version overrides it. Doctrine uses it to skip a version-detection round-trip and to select platform features; under-stating it is safe, over-stating it (a higher version than the server actually runs) can break. Set to your cluster's major version if it is not 18."
}

# ---------------------------------------------------------------------------
# App Platform component names
#
# App Platform will NOT rename a database component in a single spec change
# ("cannot create and delete a database in a single spec change"), and renaming
# the service also churns ingress. When adopting an EXISTING app into this
# module, set these to the app's current component names so the migration is a
# no-op rename. For new apps, leave the defaults.
# ---------------------------------------------------------------------------

variable "service_component_name" {
  type        = string
  description = "Name of the web service component in the app spec. Set to the existing name when migrating an app already deployed under a different component name."
  default     = "web"
}

variable "database_component_name" {
  type        = string
  description = "Name of the database component in the app spec (also the binding prefix used to build DATABASE_URL). Set to the existing name when migrating; App Platform cannot rename a database component in one step."
  default     = "db"
}

# ---------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------

variable "enable_predeploy_migrations" {
  type        = bool
  description = "Add a PRE_DEPLOY job that runs docker/prod/release.sh (migrations) once per deploy. Leave false for the very first deploy — the job can't reach the DB until the one-time manual bootstrap (firewall trusted-source + schema GRANT) is done. Flip to true afterwards."
  default     = false
}

variable "migration_command" {
  type        = string
  description = "Command the PRE_DEPLOY job runs (when enabled)."
  default     = "bash docker/prod/release.sh"
}

# ---------------------------------------------------------------------------
# Background worker (optional)
# ---------------------------------------------------------------------------

variable "enable_worker" {
  type        = bool
  description = "Run a background worker component (same image as the service) with worker_command."
  default     = false
}

variable "worker_command" {
  type        = string
  description = "Run command for the worker component (required when enable_worker is true)."
  default     = ""

  validation {
    condition     = !var.enable_worker || var.worker_command != ""
    error_message = "worker_command is required when enable_worker is true."
  }
}

variable "worker_component_name" {
  type        = string
  description = "Name of the worker component."
  default     = "worker"
}

variable "worker_instance_size_slug" {
  type        = string
  description = "Instance size for the worker component. Empty means: use the service's instance_size_slug."
  default     = ""
}

variable "worker_instance_count" {
  type        = number
  description = "Number of worker instances."
  default     = 1
}

# ---------------------------------------------------------------------------
# Custom domain (optional)
# ---------------------------------------------------------------------------

variable "custom_domain" {
  type        = string
  description = "Custom domain to attach (e.g. app.example.com). Empty to serve only on the assigned *.ondigitalocean.app URL."
  default     = ""
}

variable "domain_zone" {
  type        = string
  description = "DO-managed DNS zone for the custom domain (usually the apex). Set to have App Platform manage the DNS record automatically; empty to point DNS yourself."
  default     = ""
}

variable "default_uri" {
  type        = string
  description = "Absolute base URL for CLI-generated URLs (DEFAULT_URI). Empty to derive https://<custom_domain>. Without a custom domain, set to the assigned *.ondigitalocean.app URL after the first deploy."
  default     = ""
}

# ---------------------------------------------------------------------------
# Application environment
# ---------------------------------------------------------------------------

variable "messenger_transport_dsn" {
  type        = string
  description = "Symfony MESSENGER_TRANSPORT_DSN."
  default     = "doctrine://default?auto_setup=0"
}

variable "app_share_dir" {
  type        = string
  description = "APP_SHARE_DIR. Note: App Platform instances are ephemeral; this path does not persist across deploys or span instances."
  default     = "var/share"
}

variable "extra_env" {
  type = map(object({
    value = string
    type  = optional(string, "GENERAL") # GENERAL or SECRET
    scope = optional(string, "RUN_TIME")
  }))
  default     = {}
  description = "Project-specific env vars merged into the app-level env, keyed by name (e.g. { APP_MULTITENANT = { value = \"1\" }, ADMIN_EMAIL = { value = \"you@example.com\" } }). SECRET-typed values still land in Terraform state — treat state as sensitive."
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

variable "app_secret" {
  type        = string
  sensitive   = true
  description = "Symfony APP_SECRET. Generate once (openssl rand -hex 16); inject via TF_VAR_app_secret."
}

variable "app_encryption_key" {
  type        = string
  sensitive   = true
  description = "APP_ENCRYPTION_KEY: base64-encoded 32-byte libsodium secret-box key. Generate once; inject via TF_VAR_app_encryption_key."
}

variable "mailer_dsn" {
  type        = string
  sensitive   = true
  description = "Production MAILER_DSN. Defaults to a no-op transport."
  default     = "null://null"
}

# ── Mercure hub (opt-in) ──────────────────────────────────────────────────
# Runs a hub as a second service in the same app and routes a path on the app's
# own domain to it, so publishers (the app, internally) and subscribers (a
# developer's machine, publicly) both reach it without a separate deployment.

variable "enable_mercure" {
  type        = bool
  default     = false
  description = "Run a Mercure hub component and route mercure_path on the app's domain to it. Also injects MERCURE_URL and MERCURE_PUBLIC_URL into the app env, so consuming apps need not set them."
}

variable "mercure_image" {
  type        = string
  default     = "dunglas/mercure"
  description = "Docker Hub image for the hub. Pin a tag in production rather than tracking latest."
}

variable "mercure_image_tag" {
  type        = string
  default     = "latest"
  description = "Tag for mercure_image."
}

variable "mercure_component_name" {
  type        = string
  default     = "mercure"
  description = "Name of the hub component in the app spec. Also its internal hostname."
}

variable "mercure_path" {
  type        = string
  default     = "/.well-known/mercure"
  description = "Path on the app's domain routed to the hub. Must be more specific than the web service's catch-all, which it is routed ahead of."
}

variable "mercure_jwt_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Shared key signing publisher and subscriber JWTs. Required when enable_mercure is true; the app signs with the same value via MERCURE_JWT_SECRET."

  validation {
    condition     = !var.enable_mercure || var.mercure_jwt_secret != ""
    error_message = "mercure_jwt_secret is required when enable_mercure is true."
  }
}

variable "mercure_instance_size_slug" {
  type        = string
  default     = ""
  description = "Instance size for the hub. Empty means: use the service's instance_size_slug."
}

variable "mercure_extra_directives" {
  type        = string
  default     = ""
  description = "Extra Caddy directives for the hub (MERCURE_EXTRA_DIRECTIVES), e.g. cors_origins. Empty leaves the image defaults."
}
