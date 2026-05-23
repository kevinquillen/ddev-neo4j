# ddev-neo4j

[![tests](https://github.com/ddev/ddev-neo4j/actions/workflows/tests.yml/badge.svg)](https://github.com/ddev/ddev-neo4j/actions/workflows/tests.yml)
![Add-on Registry](https://img.shields.io/badge/DDEV%20add--on-neo4j-blue)
![Project is maintained](https://img.shields.io/maintenance/yes/2026)

A [DDEV](https://ddev.com/) add-on that provisions a [Neo4j](https://neo4j.com/)
graph database service alongside your DDEV project. Designed to be
zero-config for Drupal sites that consume Neo4j (e.g.
[`content_graph_neo4j`](https://github.com/velir/content_graph)) but
useful for any DDEV project that needs a local graph database.

## What you get

- A Neo4j 5 (community) container reachable from the web container at
  `bolt://neo4j:7687` and `http://neo4j:7474`.
- The Neo4j Browser UI at `https://<project>.ddev.site:7475`, with a
  valid TLS cert provided by DDEV's router.
- The [APOC](https://neo4j.com/labs/apoc/) and
  [Graph Data Science](https://neo4j.com/docs/graph-data-science/current/)
  plugins enabled by default.
- Named persistent volumes for graph data, logs, and plugins that
  survive `ddev stop` and are wiped only by `ddev add-on remove neo4j`.
- For Drupal projects: a `settings.ddev.neo4j.php` snippet wired into
  `sites/default/settings.php` that populates
  `$settings['content_graph_neo4j']` so the Drupal side connects with
  no extra wiring.

## Install

```bash
ddev add-on get ddev/ddev-neo4j
ddev restart
```

First boot takes ~30 seconds while Neo4j downloads and installs APOC
and GDS into the plugins volume; subsequent boots are fast.

Open the Browser UI:

```bash
ddev launch :7475
# or visit https://<project>.ddev.site:7475 directly
```

Default credentials:

| Setting | Value |
| --- | --- |
| Username | `neo4j` |
| Password | `ddevpassword` (override via `.ddev/config.neo4j.yaml`) |

## Connect from your project

### From PHP (Drupal-ready)

If your project type is Drupal, the add-on writes
`web/sites/default/settings.ddev.neo4j.php` and includes it from
`settings.php`. It populates:

```php
$settings['content_graph_neo4j'] = [
  'uri' => 'bolt://neo4j:7687',
  'username' => 'neo4j',
  'password' => getenv('DDEV_NEO4J_PASSWORD') ?: 'ddevpassword',
  'database' => getenv('DDEV_NEO4J_DATABASE') ?: 'neo4j',
];
```

Sites that need bespoke credentials can simply not include the file
and define their own block.

### From the CLI

```bash
ddev exec cypher-shell -a bolt://neo4j:7687 -u neo4j -p ddevpassword
```

### From any client inside the web container

| Endpoint | Address |
| --- | --- |
| Bolt | `bolt://neo4j:7687` |
| HTTP | `http://neo4j:7474` |

## Configuration overrides

The add-on ships `.ddev/config.neo4j.yaml` for per-project tuning.
Edit it and run `ddev restart`:

```yaml
web_environment:
  - DDEV_NEO4J_PASSWORD=ddevpassword
  - DDEV_NEO4J_DATABASE=neo4j
  - DDEV_NEO4J_HEAP_INITIAL=512m
  - DDEV_NEO4J_HEAP_MAX=1G
  - DDEV_NEO4J_PAGECACHE=512m
  - NEO4J_PLUGINS=["apoc", "graph-data-science"]
  - NEO4J_DOCKER_IMAGE=neo4j:5-community
  - NEO4J_ACCEPT_LICENSE_AGREEMENT=no
```

To claim ownership of the file (so a future `ddev add-on get` won't
overwrite your edits), delete the `#ddev-generated` marker comment at
the top.

### Use Neo4j Enterprise (opt-in)

```yaml
web_environment:
  - NEO4J_DOCKER_IMAGE=neo4j:5-enterprise
  - NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
```

You are responsible for complying with Neo4j's commercial license.

### Disable plugins

```yaml
web_environment:
  - NEO4J_PLUGINS=[]
```

### Low-memory hosts

```yaml
web_environment:
  - DDEV_NEO4J_HEAP_MAX=512m
  - DDEV_NEO4J_PAGECACHE=256m
```

## Wipe the database

Three options, in order of severity:

```bash
# Drop all nodes/relationships, keep credentials and config.
ddev exec cypher-shell -a bolt://neo4j:7687 -u neo4j -p ddevpassword \
  'MATCH (n) DETACH DELETE n'

# Remove the data volume only.
ddev stop
docker volume rm "ddev-${DDEV_PROJECT:-$(basename $PWD)}-neo4j-data"
ddev start

# Remove the add-on entirely (wipes data, logs, plugin caches,
# Drupal settings include).
ddev add-on remove neo4j
```

## Compatibility

| Layer | Tested | Notes |
| --- | --- | --- |
| DDEV CLI | 1.24.10+ | Required for `x-ddev` describe extensions |
| Neo4j | 5.x community | 5-enterprise supported as opt-in |
| Plugins | APOC 5.x, GDS 2.x | Pinned to Neo4j 5 |
| Host OS | macOS (Apple Silicon + Intel), Linux x86_64 | Multi-arch image |
| Drupal | 9, 10, 11 | Settings injection is conditional on `PROJECT_TYPE` |

## Operational notes

- **Cold-start time.** First boot is ~30s while plugins install. The
  web container waits on Neo4j's healthcheck, so `ddev start` blocks
  briefly. This is not a hang.
- **Memory.** Defaults consume ~1.5 GB resident. Tune
  `DDEV_NEO4J_HEAP_MAX` and `DDEV_NEO4J_PAGECACHE` if your Docker VM
  is smaller.
- **Bolt is plaintext** inside the DDEV network. Fine for local dev;
  configure TLS at the Neo4j level if you need to expose Bolt
  externally (uncommon in DDEV).
- **Volume naming.** Volumes are scoped per project as
  `ddev-<project>-neo4j-{data,logs,plugins}`, so multiple DDEV sites
  on the same host don't collide.

## Removing the add-on

```bash
ddev add-on remove neo4j
```

This removes:

- `.ddev/docker-compose.neo4j.yaml`
- `.ddev/config.neo4j.yaml`
- `.ddev/neo4j/conf/neo4j.conf`
- `.ddev/settings.ddev.neo4j.php`
- The Drupal `settings.php` include block (left intact if you
  modified it).
- The `ddev-<project>-neo4j-{data,logs,plugins}` Docker volumes.

## Testing

```bash
brew install bats-core bats-assert bats-file bats-support
bats ./tests/test.bats
```

CI runs the same suite via
[`ddev/github-action-add-on-test`](https://github.com/ddev/github-action-add-on-test)
on every PR, every push to `main`, and weekly on a cron schedule.

## License

Apache 2.0. See [LICENSE](LICENSE).

Neo4j community edition is GPL v3; Neo4j enterprise edition is
commercial. APOC is Apache 2.0; Graph Data Science community edition
is GPL v3. You are responsible for compliance with their respective
licenses when running the add-on.
