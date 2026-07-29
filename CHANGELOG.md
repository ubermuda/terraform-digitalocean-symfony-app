# Changelog

All notable changes to this module are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the git
tags consumers pin via `?ref=`.

## [Unreleased]

### Added

- Optional **dedicated Postgres cluster**. `create_db_cluster = true` makes the
  module create and own a cluster named `<app_name>-db` for this app instead of
  attaching to an existing one, so a consumer starting from nothing no longer
  needs a manual `doctl databases create` before the first apply. Sized by
  `db_cluster_size` (default `db-s-1vcpu-1gb`), `db_cluster_node_count`
  (default `1`), `db_cluster_version` (default: `database_server_version`),
  `db_cluster_region` (default `tor1` — a **datacenter** slug, a different
  namespace from App Platform's `region`, validated as such) and
  `db_cluster_tags`. The cluster is guarded with `prevent_destroy`, and a
  `check` block warns when it is not colocated with the app.
- In dedicated mode the module also manages the cluster's **trusted sources**
  (the app itself, plus `db_cluster_trusted_ips`), removing the manual
  `doctl databases firewalls append` step. This stays out of bring-your-own
  mode, where the resource is authoritative and would cut off sibling apps.
- Outputs `db_cluster_name`, `db_cluster_host` and `db_cluster_created`;
  `db_cluster_id` now resolves in both modes. A consuming root does not
  special-case on the mode.

### Changed

- `db_cluster_name`'s default is now `""`, meaning "the historical default
  shared cluster (`app-22613a04-…`)", which is resolved internally. **No
  behaviour change and no plan diff** for existing consumers, whether they set
  the variable or relied on the old literal default. The empty default is what
  lets the module tell "not set" from "set", so combining it with
  `create_db_cluster` can be rejected at plan time.
- Examples' `required_version` raised from `>= 1.5` to `>= 1.9`, matching the
  module floor they call.

## [1.6.0] - 2026-07-27

### Added

- Opt-in Mercure hub component (`enable_mercure`, `mercure_jwt_secret`,
  `mercure_image`, `mercure_image_tag`, `mercure_component_name`,
  `mercure_path`, `mercure_instance_size_slug`, `mercure_extra_directives`).
  Runs `dunglas/mercure` as a second service and routes `mercure_path` on the
  app's own domain to it, so publishers reach it privately and subscribers
  publicly without a separate deployment. `MERCURE_URL`, `MERCURE_PUBLIC_URL`
  and `MERCURE_JWT_SECRET` are injected into the app env automatically.

## [1.5.0] - 2026-07-22

### Added

- Opt-in worker component (`enable_worker`, `worker_command`,
  `worker_component_name`, `worker_instance_size_slug`, `worker_instance_count`)
  — same image as the service, supervised by App Platform.

### Changed

- Minimum Terraform version raised from 1.5 to 1.9 (cross-variable validation on worker_command).

## [1.4.0] - 2026-07-03

### Added

- `database_server_version` variable (default `18`) controlling the
  `serverVersion` hint appended to the components' `DATABASE_URL`.

### Fixed

- `DATABASE_URL`'s `serverVersion` was hardcoded to `16` while the default shared
  cluster runs PostgreSQL 18, so Doctrine ran against a stale platform version.
  It now defaults to `18` (matching the default cluster) and is overridable via
  `database_server_version`. **Behavior change:** existing deployments that relied
  on the hardcoded `16` will see `serverVersion` become `18` on the next apply;
  consumers on a non-18 cluster must set `database_server_version` to their major
  version.

## [1.3.0] - 2026-07-02

### Added

- `image_repository`, `db_name`, and `db_user` now default off `app_name`
  (the DB names convert hyphens to underscores for a valid Postgres identifier).
  A new consumer only needs to set `app_name` plus the three secrets; all three
  remain overridable.

## [1.2.0] - 2026-07-02

### Added

- `service_component_name` and `database_component_name` variables (default
  `web` / `db`) so an already-deployed app can be adopted without renaming its
  App Platform components. App Platform rejects renaming a **database** component
  in a single spec change (`cannot create and delete a database in a single spec
  change`); set these to the existing names for a no-op adoption.

## [1.1.0] - 2026-07-02

### Fixed

- Manage the `ingress` rule explicitly (route `/` to the web service). App
  Platform treats `ingress` as Optional+Computed, so adopting an app that already
  had an ingress rule previously sent an inconsistent spec (the stale rule pointed
  at the old component) and was rejected.

## [1.0.0] - 2026-07-02

### Added

- Initial release. Deploys a prebuilt Symfony image to DigitalOcean App Platform
  and attaches a per-app database (`digitalocean_database_db` + `_user`, guarded
  with `prevent_destroy`) on an existing **shared** managed Postgres cluster.
  Includes an optional custom domain, an opt-in `PRE_DEPLOY` migration job, an
  `extra_env` passthrough for project-specific variables, and outputs for
  `app_id` / `live_url` / `default_ingress` / `db_cluster_id` / `db_name` /
  `db_user`. Deliberately does **not** manage a `digitalocean_database_firewall`
  (authoritative — it would cut off the sibling apps on the shared cluster);
  trusted sources and schema grants are a documented manual step.
