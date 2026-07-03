# terraform-digitalocean-symfony-app

Terraform module that deploys a Symfony app (built from the `symfony-skeleton`)
to **DigitalOcean App Platform**, running a **prebuilt** image and attaching a
per-app database on an **existing shared** managed Postgres cluster.

One module, many apps: qualendar, make-plans, and any skeleton-derived project
call this with their own variables. Common shape lives here; per-project
differences go through `extra_env` and resources in the consumer's own root.

## Usage

```hcl
# versions.tf (root) — provider + backend live in the ROOT, not the module.
provider "digitalocean" {
  token = var.do_token
}

# main.tf (root)
module "app" {
  source = "git::https://github.com/ubermuda/terraform-digitalocean-symfony-app.git//?ref=v1.3.0"

  app_name = "my-app" # image repo + db name/user default off this

  registry_credentials = var.registry_credentials # GHCR "user:PAT"
  app_secret           = var.app_secret
  app_encryption_key   = var.app_encryption_key

  # Optional:
  # image_repository            = "..."   # defaults to app_name
  # db_name / db_user           = "..."   # default off app_name (hyphens->underscores)
  # custom_domain               = "app.example.com"
  # domain_zone                 = "example.com"
  # enable_predeploy_migrations = true
  # extra_env = { APP_MULTITENANT = { value = "1" } }
}
```

For a new app, `app_name` + the three secrets is all you need — everything else
has a default. Then run the one-time DB bootstrap (`just tf-db-bootstrap`).

Always pin `?ref=` to a tag or commit — never track a moving branch. A complete,
validatable root is in [`examples/complete/`](examples/complete).

## What it creates

- A dedicated **database + user** on the shared cluster (guarded with
  `prevent_destroy`).
- A `digitalocean_app` with a **web** service (nginx + php-fpm on :80), the
  database attached as component `db`, an optional custom domain, and an
  **opt-in** `PRE_DEPLOY` migration job.

The image is **not** built by App Platform — build and push it yourself (e.g. a
`just build-prod` recipe) and point `registry_*` / `image_*` at it.

## Per-project differences

- **`extra_env`** — a map of env vars merged into the app-level env, e.g.
  `{ ADMIN_EMAIL = { value = "x@y.z" }, SECRET_THING = { value = "…", type = "SECRET" } }`.
- **Extra resources** (DNS records, etc.) go in the consumer root *next to* the
  module call, not inside it.

## Inputs (summary)

| Name | Required | Default | Notes |
|---|---|---|---|
| `app_name` | ✓ | — | App Platform app name; base for the defaults below |
| `app_secret`, `app_encryption_key` | ✓ | — | Inject via `TF_VAR_*` |
| `image_repository` | | `app_name` | Repo within the registry |
| `db_name`, `db_user` | | from `app_name` | `db_name` = app_name with `-`→`_`; `db_user` = `db_name` |
| `region` | | `tor` | Must match the DB cluster's region |
| `registry_type` / `registry` | | `GHCR` / `ubermuda` | Also `DOCR`, `DOCKER_HUB` |
| `registry_credentials` | | `""` | Required for GHCR/private Docker Hub |
| `image_tag` | | `prod` | |
| `db_cluster_name` | | `app-22613a04-…` | The shared cluster (name = the app-… string) |
| `service_component_name` / `database_component_name` | | `web` / `db` | Set to existing names when adopting a deployed app |
| `enable_predeploy_migrations` | | `false` | Turn on after first-deploy bootstrap |
| `custom_domain` / `domain_zone` / `default_uri` | | `""` | Optional custom domain |
| `extra_env` | | `{}` | Project-specific env passthrough |

See `variables.tf` for the full list and descriptions. Outputs: `app_id`,
`live_url`, `default_ingress`, `db_cluster_id`, `db_name`, `db_user`.

## Manual database bootstrap (NOT in Terraform — and can't be)

The DO **API exposes no** resource for Postgres privileges/grants, and a
`digitalocean_database_firewall` resource is **authoritative** — on this
**shared** cluster it would replace the whole trusted-source list and cut off the
sibling apps. So two steps are done by hand, once per app. Without them the DB
connection **times out** and migrations fail.

**1. Trusted sources** — allow the app (and your IP) to reach the DB:

```sh
CID=$(terraform output -raw db_cluster_id)
APP_ID=$(terraform output -raw app_id)
doctl databases firewalls append "$CID" --rule app:"$APP_ID"     # additive — keeps siblings
doctl databases firewalls append "$CID" --rule ip_addr:<YOUR_IP> # to run the grant below
```

**2. Schema privileges** — PG15+ blocks `CREATE` on `public` for a plain user, so
migrations fail with `SQLSTATE[42501] permission denied for schema public`. Grant
once, as the cluster admin:

```sh
CID=$(terraform output -raw db_cluster_id)
DB=$(terraform output -raw db_name); USER=$(terraform output -raw db_user)
eval "$(doctl databases connection "$CID" --format Host,Port,User,Password --no-header \
  | awk '{print "export PGHOST="$1" PGPORT="$2" PGUSER="$3" PGPASSWORD="$4}')"
php -r '$p=new PDO(sprintf("pgsql:host=%s;port=%s;dbname=%s;sslmode=require",getenv("PGHOST"),getenv("PGPORT"),getenv("DB")),getenv("PGUSER"),getenv("PGPASSWORD"),[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$u=getenv("USER");$d=getenv("DB");$p->exec("GRANT ALL ON SCHEMA public TO \"$u\"");$p->exec("GRANT ALL PRIVILEGES ON DATABASE \"$d\" TO \"$u\"");echo "ok\n";' \
  DB="$DB" USER="$USER"
```

Then run migrations once (`docker run --rm --env-file … <image> docker/prod/release.sh`)
and set `enable_predeploy_migrations = true` for automated migrations thereafter.

## Notes

- **State is sensitive.** SECRET env plaintext lives in state — use an encrypted
  remote backend (see `examples/complete/versions.tf`).
- **Tearing down data.** `prevent_destroy` makes `terraform destroy` error on the
  db/user. To intentionally remove them, `terraform state rm` first (or drop by
  hand). The shared cluster is a data source and is never touched regardless.
- **Region must match the DB.** Colocate app and cluster (both `tor`).
