# CloudNativePG Babelfish

CloudNativePG-compatible Docker images for [Babelfish for PostgreSQL](https://babelfishpg.org/).

Babelfish is an open-source project that adds Microsoft SQL Server compatibility to PostgreSQL, enabling applications written for SQL Server to work with PostgreSQL with minimal code changes.

## Why Babelfish?

- **ARM support** - Microsoft SQL Server doesn't run on ARM architecture. Babelfish enables SQL Server workloads on ARM-based infrastructure (Apple Silicon, AWS Graviton, etc.)
- **Kubernetes-native** - Fully compatible with CloudNativePG for cloud-native deployments

## Supported Tags

| Tag           | PostgreSQL | Babelfish | Architectures |
| ------------- | ---------- | --------- | ------------- |
| `17.6-5.3.0`  | 17.6       | 5.3.0     | amd64, arm64  |
| `16.10-4.7.0` | 16.10      | 4.7.0     | amd64, arm64  |

> **Note**: PostgreSQL 18 support will be added once Babelfish releases PG18 support. Check [Babelfish releases](https://github.com/babelfish-for-postgresql/babelfish-for-postgresql/releases) for updates.

## Example

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: babelfish-cluster
spec:
  instances: 3
  imageName: ghcr.io/nasus20202/cloudnative-babelfish:17.6-5.3.0

  postgresql:
    shared_preload_libraries:
      - babelfishpg_tds

    # pg_hba rules for TDS authentication
    pg_hba:
      - host babelfish_db babelfish_user 0.0.0.0/0 md5

    parameters:
      babelfishpg_tds.listen_addresses: "*"
      babelfishpg_tds.port: "1433"
      babelfishpg_tsql.database_name: "babelfish_db"
      babelfishpg_tsql.migration_mode: "single-db"
      babelfishpg_tsql.isolation_level_serializable: "pg_isolation"

  bootstrap:
    initdb:
      database: babelfish_db
      owner: babelfish_user
      postInitTemplateSQL:
        - CREATE EXTENSION IF NOT EXISTS babelfishpg_tds CASCADE
      postInitApplicationSQL:
        - GRANT ALL ON SCHEMA sys TO babelfish_user
        - ALTER USER babelfish_user CREATEDB
        - CALL sys.initialize_babelfish('babelfish_user')

  storage:
    size: 10Gi

  # TDS services for SQL Server clients
  managed:
    services:
      additional:
        - selectorType: rw
          serviceTemplate:
            metadata:
              name: babelfish-cluster-tds-rw
            spec:
              type: ClusterIP
              ports:
                - name: tds
                  port: 1433
                  targetPort: 1433
```

See [examples/cluster-basic.yaml](examples/cluster-basic.yaml) for a full example with resource limits, affinity rules, and additional TDS services.

## Connecting via SQL Server Protocol

After deploying the cluster, connect using any SQL Server client (e.g., `sqlcmd`, SSMS, Azure Data Studio):

```bash
# Get the password from the Kubernetes secret
kubectl get secret babelfish-cluster-app -o jsonpath='{.data.password}' | base64 -d

# Connect via sqlcmd
sqlcmd -S babelfish-cluster-tds-rw -U babelfish_user -P '<password>'
```

Babelfish initializes with the standard SQL Server system databases (`master`, `tempdb`, `msdb`). **User databases must be created separately** via TDS:

```sql
CREATE DATABASE myapp;
GO
USE myapp;
GO
```

## Automated Dependency Updates

This repository uses [Renovate](https://docs.renovatebot.com/) to automatically update dependencies:

### What Gets Updated

- **Babelfish Versions**: Automatically detects new Babelfish releases from [babelfish-for-postgresql/babelfish-for-postgresql](https://github.com/babelfish-for-postgresql/babelfish-for-postgresql/releases)
  - Updates version strings in `Dockerfile`, GitHub workflows, `Makefile`, and `docker-bake.hcl`
  - Tracks both the full version format (e.g., `BABEL_5_3_0__PG_17_6`) and semantic versions (e.g., `5.3.0`)
  - Updates bundled PostgreSQL versions that come with Babelfish releases

- **GitHub Actions**: Minor and patch updates to GitHub Actions are auto-merged

- **Docker Base Images**: Updates to Debian base images (requires manual approval)

### Configuration

The Renovate configuration is in [`renovate.json`](./renovate.json). It uses custom regex managers to detect and update Babelfish version strings across multiple files:

1. **Version String Manager**: Detects patterns like `BABELFISH_VERSION=BABEL_5_3_0__PG_17_6`
2. **Semantic Version Manager**: Detects patterns like `babelfish_semver: "5.3.0"`
3. **PostgreSQL Version Manager**: Detects patterns like `pg_version: "17.6"` when paired with Babelfish versions

All Babelfish-related updates are grouped into a single PR for easier review and testing.
