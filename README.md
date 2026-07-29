# terraform-digitalocean-symfony-app

Terraform module that deploys a Symfony app (built from the `symfony-skeleton`)
to **DigitalOcean App Platform**, running a **prebuilt** image, with a managed
Postgres database it can either **attach to a cluster you already have** or
**create a dedicated cluster** for.

One module, many apps: qualendar, make-plans, and any skeleton-derived project
call this with their own variables. Common shape lives here; per-project
differences go through `extra_env` and resources in the consumer's own root.

## Database: two modes

| | `create_db_cluster = false` (default) | `create_db_cluster = true` |
|---|---|---|
| Cluster | **Bring your own** — an existing one, read as a data source | **Dedicated** — created and owned by this state |
| Named by | `db_cluster_name` (empty = the default shared cluster) | derived: `<app_name>-db` |
| Cost | shared with whatever else is on it | a whole cluster, billed hourly |
| Trusted sources | manual (`doctl databases firewalls append`) | managed by the module |
| Destroyed by `terraform destroy` | never — it is a data source | no — `prevent_destroy` |

Setting `create_db_cluster = true` **and** `db_cluster_name` is rejected at plan
time: one names a cluster to attach to, the other asks for a new one.

Both modes create the per-app database and user (`db_name` / `db_user`) and
attach them to the app as the `db` component, so nothing downstream changes —
`DATABASE_URL` and the `db_cluster_*` outputs are the same either way.

## Usage

**Bring your own cluster** (the default — unchanged from earlier versions):

```hcl
# versions.tf (root) — provider + backend live in the ROOT, not the module.
provider "digitalocean" {
  token = var.do_token
}

# main.tf (root)
module "app" {
  source = "git::https://github.com/ubermuda/terraform-digitalocean-symfony-app.git//?ref=v1.7.0"

  app_name = "my-app" # image repo + db name/user default off this

  registry_credentials = var.registry_credentials # GHCR "user:PAT"
  app_secret           = var.app_secret
  app_encryption_key   = var.app_encryption_key

  # Optional:
  # db_cluster_name             = "app-…"  # the cluster to attach to; empty = the default shared one
  # image_repository            = "..."   # defaults to app_name
  # db_name / db_user           = "..."   # default off app_name (hyphens->underscores)
  # custom_domain               = "app.example.com"
  # domain_zone                 = "example.com"
  # enable_predeploy_migrations = true
  # extra_env = { APP_MULTITENANT = { value = "1" } }
}
```

**Create a dedicated cluster** — for anyone starting with no Postgres cluster
at all, so the first `apply` is self-sufficient:

```hcl
module "app" {
  source = "git::https://github.com/ubermuda/terraform-digitalocean-symfony-app.git//?ref=v1.7.0"

  app_name          = "my-app"
  create_db_cluster = true # creates "my-app-db" in `region`

  registry_credentials = var.registry_credentials
  app_secret           = var.app_secret
  app_encryption_key   = var.app_encryption_key

  # Sizing — defaults shown. The cluster is billed for as long as it exists.
  # db_cluster_size        = "db-s-1vcpu-1gb" # smallest managed PG plan
  # db_cluster_node_count  = 1                # no standby node
  # db_cluster_version     = ""               # "" = database_server_version (18)
  # db_cluster_region      = ""               # "" = region
  # db_cluster_trusted_ips = ["203.0.113.7"]  # your address, for the one-time GRANT
}
```

For a new app, `app_name` + the three secrets is all you need — everything else
has a default. Then run the one-time DB bootstrap below.

Always pin `?ref=` to a tag or commit — never track a moving branch. Complete,
validatable roots are in [`examples/complete/`](examples/complete) (bring your
own) and [`examples/dedicated-cluster/`](examples/dedicated-cluster).

## What it creates

- Optionally (`create_db_cluster = true`) a **dedicated Postgres cluster**
  named `<app_name>-db`, plus its trusted-source list (guarded with
  `prevent_destroy`). Off by default; without it an existing cluster is read as
  a data source and never modified.
- A per-app **database + user** on whichever cluster is in play (guarded with
  `prevent_destroy`).
- A `digitalocean_app` with a **web** service (nginx + php-fpm on :80), the
  database attached as component `db`, an optional custom domain, an
  **opt-in** `PRE_DEPLOY` migration job, and an **opt-in background worker**
  component (same image, running `worker_command`).

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
| `create_db_cluster` | | `false` | `true` creates a dedicated cluster instead of attaching to one |
| `db_cluster_name` | | `""` (= `app-22613a04-…`) | Bring-your-own only: the existing cluster (name = the app-… string). Rejected with `create_db_cluster` |
| `db_cluster_size` | | `db-s-1vcpu-1gb` | Dedicated only: cluster plan |
| `db_cluster_node_count` | | `1` | Dedicated only: 1 = no standby |
| `db_cluster_version` | | `""` (= `database_server_version`) | Dedicated only: PG major version |
| `db_cluster_region` | | `""` (= `region`) | Dedicated only: keeps app and DB colocated |
| `db_cluster_tags` | | `[]` | Dedicated only: tags on the created cluster |
| `db_cluster_trusted_ips` | | `[]` | Dedicated only: extra IPs/CIDRs allowed in, on top of the app |
| `database_server_version` | | `18` | PG major version for `DATABASE_URL`'s `serverVersion`; match the cluster (default cluster is PG 18) |
| `service_component_name` / `database_component_name` | | `web` / `db` | Set to existing names when adopting a deployed app |
| `enable_predeploy_migrations` | | `false` | Turn on after first-deploy bootstrap |
| `enable_worker` | | `false` | Run a background worker component |
| `worker_command` | | `""` | Required when `enable_worker` is `true` |
| `worker_component_name` | | `worker` | Name of the worker component |
| `worker_instance_size_slug` | | `""` (= `instance_size_slug`) | Instance size for the worker |
| `worker_instance_count` | | `1` | Number of worker instances |
| `custom_domain` / `domain_zone` / `default_uri` | | `""` | Optional custom domain |
| `extra_env` | | `{}` | Project-specific env passthrough |

See `variables.tf` for the full list and descriptions. Outputs: `app_id`,
`live_url`, `default_ingress`, `db_cluster_id`, `db_cluster_name`,
`db_cluster_host`, `db_cluster_created`, `db_name`, `db_user`. The
`db_cluster_*` outputs resolve to whichever mode is active, so a consuming root
does not special-case.

## Database bootstrap

Two things Terraform cannot do for you on a shared cluster. **How much is
manual depends on the mode.**

**1. Trusted sources.**

*Bring-your-own mode:* manual. `digitalocean_database_firewall` is
**authoritative** — on a shared cluster it would replace the whole
trusted-source list and cut off the sibling apps — so the module deliberately
does not manage it:

```sh
CID=$(terraform output -raw db_cluster_id)
APP_ID=$(terraform output -raw app_id)
doctl databases firewalls append "$CID" --rule app:"$APP_ID"     # additive — keeps siblings
doctl databases firewalls append "$CID" --rule ip_addr:<YOUR_IP> # to run the grant below
```

*Dedicated mode:* done by `terraform apply`. The module owns the cluster, so it
declares the trusted sources: the app itself, plus anything in
`db_cluster_trusted_ips`. That list is authoritative — a rule appended with
`doctl` is removed on the next apply, so put your address in the variable
instead:

```hcl
db_cluster_trusted_ips = ["203.0.113.7"] # remove again after the grant below
```

**2. Schema privileges** — manual in **both** modes; the DO **API exposes no**
resource for Postgres grants, and creating the cluster does not make the app's
user the owner of `public`. PG15+ blocks `CREATE` on `public` for a plain user, so
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

## Mercure hub

Set `enable_mercure = true` and supply `mercure_jwt_secret` to run a hub as a
second service in the same app:

```hcl
enable_mercure     = true
mercure_jwt_secret = var.mercure_jwt_secret   # same value the app signs with
```

The module routes `mercure_path` (default `/.well-known/mercure`) on the app's
own domain to the hub, listing that rule **before** the web service's `/`
catch-all, and injects `MERCURE_URL`, `MERCURE_PUBLIC_URL` and
`MERCURE_JWT_SECRET` into the app environment — a consuming app does not set
them itself.

Two addresses are needed because they have different audiences: the application
publishes over the app's private network (`http://<component>/…`), while
subscribers are typically outside it — a browser, or a CLI on a developer's
machine — and need the public route.

The hub is **in-memory**: delivery is best effort and a restart drops
undelivered updates. Publishers that need durability should keep their own
outbox and replay. `mercure_image_tag` defaults to `latest`; pin it for
production.


## Notes

- **State is sensitive.** SECRET env plaintext lives in state — use an encrypted
  remote backend (see `examples/complete/versions.tf`).
- **Tearing down data.** `prevent_destroy` makes `terraform destroy` error on the
  db/user — and, in dedicated mode, on the cluster itself. To intentionally
  remove them, `terraform state rm` first (or drop by hand). The same guard
  means flipping `create_db_cluster` back to `false` **errors** instead of
  destroying a cluster holding the whole application database; that is on
  purpose. In bring-your-own mode the cluster is a data source and is never
  touched regardless.
- **Region must match the DB.** Colocate app and cluster. In dedicated mode
  that is automatic (`db_cluster_region` defaults to `region`); in
  bring-your-own mode set `region` to the existing cluster's region.
- **A dedicated cluster costs money for as long as it exists**, independently of
  the app. `db_cluster_size` defaults to the smallest managed plan and
  `db_cluster_node_count` to 1 (no standby: a node failure is downtime, and
  DO's daily backups are the recovery path). Raise both deliberately.
