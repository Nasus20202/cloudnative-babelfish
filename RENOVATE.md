# Renovate Configuration Guide

This document explains how the Renovate configuration works for automatic dependency updates in this repository.

## Overview

This repository uses [Renovate](https://docs.renovatebot.com/) to automatically detect and update:

1. **Babelfish for PostgreSQL** releases
2. **GitHub Actions** versions
3. **Docker base images** (Debian)

## How It Works

### Babelfish Version Detection

Babelfish releases follow a specific naming pattern: `BABEL_X_Y_Z__PG_XX_YY`
- Example: `BABEL_5_3_0__PG_17_6` represents Babelfish v5.3.0 with PostgreSQL 17.6

Renovate monitors the [babelfish-for-postgresql/babelfish-for-postgresql](https://github.com/babelfish-for-postgresql/babelfish-for-postgresql) repository for new releases and updates version strings across multiple files using custom regex managers.

### Files Monitored

The configuration tracks Babelfish versions in:

1. **Dockerfile**
   ```dockerfile
   ARG BABELFISH_VERSION=BABEL_5_3_0__PG_17_6
   ```

2. **GitHub Workflows** (`.github/workflows/build-and-push.yaml`)
   ```yaml
   babelfish_version: "BABEL_5_3_0__PG_17_6"
   babelfish_semver: "5.3.0"
   pg_version: "17.6"
   ```

3. **Makefile**
   ```makefile
   PG17_VERSION = BABEL_5_3_0__PG_17_6
   PG16_VERSION = BABEL_4_7_0__PG_16_10
   ```

4. **docker-bake.hcl**
   ```hcl
   "17.6-5.3.0" = {
     babelfish_version = "BABEL_5_3_0__PG_17_6"
     pg_version        = "17.6"
     babelfish_semver  = "5.3.0"
   }
   ```

### Custom Managers

The configuration uses three custom regex managers:

#### 1. Version String Manager
**Purpose**: Detects and updates the full Babelfish version string

**Pattern**: `BABEL_X_Y_Z__PG_XX_YY`

**Matches**:
- `ARG BABELFISH_VERSION=BABEL_5_3_0__PG_17_6`
- `babelfish_version: "BABEL_5_3_0__PG_17_6"`
- `PG17_VERSION = BABEL_5_3_0__PG_17_6`

#### 2. Semantic Version Manager
**Purpose**: Updates semantic version strings (X.Y.Z format)

**Pattern**: `\d+\.\d+\.\d+`

**Matches**:
- `babelfish_semver: "5.3.0"`

#### 3. PostgreSQL Version Manager
**Purpose**: Updates PostgreSQL versions bundled with Babelfish

**Pattern**: `pg_version: "XX.YY"` (paired with Babelfish version)

**Matches**:
- `pg_version: "17.6"` when followed by `babelfish_version: "BABEL_5_3_0__PG_17_6"`

## Update Behavior

### Automatic Updates

- **GitHub Actions**: Minor and patch updates are automatically merged
- **Babelfish**: Updates are grouped into a single PR for review (not auto-merged)
- **Docker Images**: Updates require manual approval

### Pull Request Grouping

All Babelfish-related updates (version strings, semantic versions, and PostgreSQL versions) are grouped into a single pull request with the group name "Babelfish". This makes it easier to:

1. Review all related changes together
2. Test the new version comprehensively
3. Deploy updates atomically

## Testing the Configuration

To validate the Renovate configuration:

```bash
# Install renovate (if not installed)
npm install -g renovate

# Validate the configuration
npx renovate-config-validator
```

You can also use Renovate's [Configuration Validator](https://docs.renovatebot.com/config-validation/) to check for errors.

## Manual Testing

To manually test if Renovate will detect updates:

1. Check the latest Babelfish release: https://github.com/babelfish-for-postgresql/babelfish-for-postgresql/releases
2. Compare with versions in the repository
3. If there's a newer version, Renovate should create a PR

## Troubleshooting

### Renovate Not Creating PRs

- Check if Renovate is enabled on the repository
- Verify the configuration is valid using `npx renovate-config-validator`
- Check Renovate logs in the repository settings

### Regex Not Matching

If Renovate isn't detecting a version string:

1. Test the regex pattern manually
2. Ensure the version string format matches the pattern
3. Check the file is included in `fileMatch` arrays

### Updates Not Appearing

- Ensure the version string exactly matches the GitHub release tag
- Check if there's a newer release in the upstream repository
- Verify the `extractVersionTemplate` correctly parses the version

## Related Documentation

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Regex Manager Configuration](https://docs.renovatebot.com/modules/manager/regex/)
- [Babelfish Releases](https://github.com/babelfish-for-postgresql/babelfish-for-postgresql/releases)
