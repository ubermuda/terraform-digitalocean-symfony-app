# ---------------------------------------------------------------------------
# Identity & placement
# ---------------------------------------------------------------------------

variable "app_name" {
  type        = string
  description = "App Platform application name. Also the default for image_repository, db_name (hyphens->underscores), and db_user — so for a new app this is often the only identifier you set."
}

variable "region" {
  type        = string
  description = "App Platform region slug. MUST match the shared DB cluster's region (the app-22613a04 cluster lives in tor) so traffic stays on the private network."
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
# Shared database (existing managed cluster)
# ---------------------------------------------------------------------------

variable "db_cluster_name" {
  type        = string
  description = "Name of the existing shared Postgres cluster. For App-Platform-provisioned clusters the name IS the app-<uuid> string; pass it directly (no lookup)."
  default     = "app-22613a04-caee-4039-ad37-76858ef7c162"
}

variable "db_name" {
  type        = string
  default     = null
  description = "Per-app database created on the shared cluster. Defaults to app_name with hyphens turned into underscores (a valid Postgres identifier). Each app gets its own so siblings don't collide."
}

variable "db_user" {
  type        = string
  default     = null
  description = "Per-app database user created on the shared cluster. Defaults to the database name (db_name)."
}

variable "database_server_version" {
  type        = string
  default     = "18"
  description = "PostgreSQL major version advertised to Doctrine via the DATABASE_URL serverVersion parameter. Must match the managed cluster's engine version — the default shared cluster runs PG 18. Doctrine uses it to skip a version-detection round-trip and to select platform features; under-stating it is safe, over-stating it (a higher version than the server actually runs) can break. Set to your cluster's major version if it is not 18."
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
