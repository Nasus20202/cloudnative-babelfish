# Docker Bake configuration for CloudNativePG Babelfish images
# Usage:
#   docker buildx bake                    # Build all targets
#   docker buildx bake pg17               # Build PostgreSQL 17 images
#   docker buildx bake --push             # Build and push all images

variable "REGISTRY" {
  default = "ghcr.io"
}

variable "REPOSITORY" {
  default = "nasus20202/cloudnative-babelfish"
}

variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}

# Version matrix
variable "VERSIONS" {
  default = {
    # PostgreSQL 18 - UNCOMMENT WHEN BABELFISH RELEASES PG18 SUPPORT
    # Expected: Q4 2025 after PostgreSQL 18 GA (Sept/Oct 2025)
    # "18.0-6.0.0" = {
    #   babelfish_version = "BABEL_6_0_0__PG_18_0"  # Update with actual version
    #   pg_major          = "18"
    #   pg_version        = "18.0"
    #   babelfish_semver  = "6.0.0"
    #   latest            = true
    # }
    
    # PostgreSQL 17
    "17.6-5.3.0" = {
      babelfish_version = "BABEL_5_3_0__PG_17_6"
      pg_major          = "17"
      pg_version        = "17.6"
      babelfish_semver  = "5.3.0"
      latest            = true
    }
    # PostgreSQL 16
    "16.10-4.7.0" = {
      babelfish_version = "BABEL_4_7_0__PG_16_10"
      pg_major          = "16"
      pg_version        = "16.10"
      babelfish_semver  = "4.7.0"
      latest            = false
    }
  }
}

# Default group - builds all versions
# Add "pg18-latest" when PG18 support is available
group "default" {
  targets = ["pg17-latest", "pg16-latest"]
}

# PostgreSQL 18 group - UNCOMMENT WHEN AVAILABLE
# group "pg18" {
#   targets = ["pg18-latest"]
# }

# PostgreSQL 17 group
group "pg17" {
  targets = ["pg17-latest"]
}

# PostgreSQL 16 group
group "pg16" {
  targets = ["pg16-latest"]
}

# Base target with common settings
target "_common" {
  dockerfile = "Dockerfile"
  platforms  = PLATFORMS
  labels = {
    "org.opencontainers.image.source"      = "https://github.com/${REPOSITORY}"
    "org.opencontainers.image.vendor"      = "CloudNative Babelfish"
    "org.opencontainers.image.licenses"    = "Apache-2.0"
    "org.opencontainers.image.title"       = "CloudNativePG Babelfish"
    "org.opencontainers.image.description" = "CloudNativePG-compatible PostgreSQL with Babelfish extensions"
  }
}

# PostgreSQL 17 - Latest (5.3.0)
target "pg17-latest" {
  inherits = ["_common"]
  args = {
    BABELFISH_VERSION = "BABEL_5_3_0__PG_17_6"
    PG_MAJOR          = "17"
  }
  tags = [
    "${REGISTRY}/${REPOSITORY}:17.6-5.3.0",
    "${REGISTRY}/${REPOSITORY}:17-5.3.0",
    "${REGISTRY}/${REPOSITORY}:17",
    "${REGISTRY}/${REPOSITORY}:latest"
  ]
}

# PostgreSQL 16 - Latest (4.7.0)
target "pg16-latest" {
  inherits = ["_common"]
  args = {
    BABELFISH_VERSION = "BABEL_4_7_0__PG_16_10"
    PG_MAJOR          = "16"
  }
  tags = [
    "${REGISTRY}/${REPOSITORY}:16.10-4.7.0",
    "${REGISTRY}/${REPOSITORY}:16-4.7.0",
    "${REGISTRY}/${REPOSITORY}:16"
  ]
}

# =============================================================================
# PostgreSQL 18 - UNCOMMENT WHEN BABELFISH RELEASES PG18 SUPPORT
# Expected: Q4 2025 after PostgreSQL 18 GA (Sept/Oct 2025)
# =============================================================================
# target "pg18-latest" {
#   inherits = ["_common"]
#   args = {
#     BABELFISH_VERSION = "BABEL_6_0_0__PG_18_0"  # Update with actual version
#     PG_MAJOR          = "18"
#   }
#   tags = [
#     "${REGISTRY}/${REPOSITORY}:18.0-6.0.0",  # Update versions
#     "${REGISTRY}/${REPOSITORY}:18-6.0.0",
#     "${REGISTRY}/${REPOSITORY}:18",
#     "${REGISTRY}/${REPOSITORY}:latest"       # Move latest tag here
#   ]
# }
