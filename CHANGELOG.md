# Changelog

All notable changes to this module are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the git
tags consumers pin via `?ref=`.

## [Unreleased]

### Added

- Opt-in worker component (`enable_worker`, `worker_command`,
  `worker_component_name`, `worker_instance_size_slug`) — same image as the
  service, supervised by App Platform.

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
