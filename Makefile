# CloudNativePG Babelfish - Build Makefile
# Usage:
#   make build          - Build default image (PG 17)
#   make build-all      - Build all versions
#   make build-pg16     - Build PostgreSQL 16 image
#   make push           - Push all images to registry
#   make test           - Test the built image

REGISTRY ?= ghcr.io
REPOSITORY ?= nasus20202/cloudnative-babelfish

# Default versions
# PG18_VERSION = BABEL_6_0_0__PG_18_0  # Uncomment when available (expected Q4 2025)
PG17_VERSION = BABEL_5_3_0__PG_17_6
PG16_VERSION = BABEL_4_7_0__PG_16_10

.PHONY: help build build-all build-pg18 build-pg17 build-pg16 build-local build-local-pg17 build-local-pg16 push test clean

help:
	@echo "CloudNativePG Babelfish Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make build          Build default image (PostgreSQL 17)"
	@echo "  make build-all      Build all supported versions"
	@echo "  make build-pg18     Build PostgreSQL 18 image (when available)"
	@echo "  make build-pg17     Build PostgreSQL 17 image"
	@echo "  make build-pg16     Build PostgreSQL 16 image"
	@echo "  make build-local    Build PG17 for local arch (fast)"
	@echo "  make build-local-pg17  Build PG17 for local arch"
	@echo "  make build-local-pg16  Build PG16 for local arch"
	@echo "  make push           Build and push all images"
	@echo "  make test           Test the built images"
	@echo "  make clean          Clean build cache"
	@echo ""
	@echo "Variables:"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  REPOSITORY=$(REPOSITORY)"
	@echo ""
	@echo "Note: PostgreSQL 18 support will be added when Babelfish releases PG18 (expected Q4 2025)"

# Build default (PG 17)
build: build-pg17

# Build all versions (add build-pg18 when available)
build-all: build-pg17 build-pg16

# Build PostgreSQL 18 - UNCOMMENT WHEN BABELFISH RELEASES PG18 SUPPORT
# build-pg18:
# 	docker buildx build \
# 		--platform linux/amd64,linux/arm64 \
# 		--build-arg BABELFISH_VERSION=$(PG18_VERSION) \
# 		--build-arg PG_MAJOR=18 \
# 		-t $(REGISTRY)/$(REPOSITORY):18.0-6.0.0 \
# 		-t $(REGISTRY)/$(REPOSITORY):18 \
# 		-t $(REGISTRY)/$(REPOSITORY):latest \
# 		.

# Build PostgreSQL 17
build-pg17:
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--build-arg BABELFISH_VERSION=$(PG17_VERSION) \
		--build-arg PG_MAJOR=17 \
		-t $(REGISTRY)/$(REPOSITORY):17.6-5.3.0 \
		-t $(REGISTRY)/$(REPOSITORY):17 \
		-t $(REGISTRY)/$(REPOSITORY):latest \
		.

# Build PostgreSQL 16
build-pg16:
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--build-arg BABELFISH_VERSION=$(PG16_VERSION) \
		--build-arg PG_MAJOR=16 \
		-t $(REGISTRY)/$(REPOSITORY):16.10-4.7.0 \
		-t $(REGISTRY)/$(REPOSITORY):16 \
		.

# Build for local architecture only (faster for testing)
build-local: build-local-pg17

build-local-pg17:
	docker build \
		--build-arg BABELFISH_VERSION=$(PG17_VERSION) \
		--build-arg PG_MAJOR=17 \
		-t $(REGISTRY)/$(REPOSITORY):17.6-5.3.0 \
		-t $(REGISTRY)/$(REPOSITORY):local \
		.

build-local-pg16:
	docker build \
		--build-arg BABELFISH_VERSION=$(PG16_VERSION) \
		--build-arg PG_MAJOR=16 \
		-t $(REGISTRY)/$(REPOSITORY):16.10-4.7.0 \
		.

# Push all images using docker bake
push:
	docker buildx bake --file docker-bake.hcl --push

# Test the built image
test:
	@echo "Testing image: $(REGISTRY)/$(REPOSITORY):local"
	@docker run --rm $(REGISTRY)/$(REPOSITORY):local which initdb postgres pg_ctl pg_controldata pg_basebackup
	@docker run --rm $(REGISTRY)/$(REPOSITORY):local which barman-cloud-backup barman-cloud-restore
	@docker run --rm $(REGISTRY)/$(REPOSITORY):local postgres --version
	@echo "All tests passed!"

# Clean build cache
clean:
	docker buildx prune -f
