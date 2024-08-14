REGISTRY_IMAGE?=localhost/radare2
DOCKER_TAG?=latest
DOCKER_IMAGE?=$(REGISTRY_IMAGE):$(DOCKER_TAG)

R2_SNAP_COMMIT:=$(shell git rev-parse --short HEAD)
DEB_BUILD_ARCH?=$(shell type -p dpkg-architecture > /dev/null && dpkg-architecture -qDEB_BUILD_ARCH || uname -m | sed -e 's,i[0-9]86,i386,g' -e 's,x86_64,amd64,g' -e 's,armv.*,armhf,g' -e 's,aarch64,arm64,g' -e 's,ppc.+64le,ppc64el,g')
SNAP_ARCH?=$(DEB_BUILD_ARCH)
#ARCH_CONFIGS=$(wildcard config/*.mk)
COSIGN_ARGS?=

include versions.mk config/$(SNAP_ARCH).mk metadata.mk
MESON_VERSION?=0.64.1
DOCKER_BUILD_ARGS+= \
	--build-arg BASE_IMAGE=$(BASE_IMAGE) \
	--build-arg BASE_SNAP=$(BASE_SNAP) \
	--build-arg SNAP_ARCH=$(SNAP_ARCH) \
	--build-arg MULTIARCH=$(MULTIARCH) \
	--build-arg FRIDA_ARCH=$(FRIDA_ARCH) \
	--build-arg MESON_VERSION=$(MESON_VERSION) \
	--build-arg R2_SNAP_COMMIT=$(R2_SNAP_COMMIT) \
	--build-arg R2_VERSION=$(R2_VERSION) \
	--build-arg R2GHIDRA_VERSION=$(R2GHIDRA_VERSION) \
	--build-arg R2FRIDA_VERSION=$(R2FRIDA_VERSION) \
	--build-arg R2DEC_VERSION=$(R2DEC_VERSION) \
	--build-arg YARA_VERSION=$(YARA_VERSION) \
	--build-arg R2YARA_VERSION=$(R2YARA_VERSION) \
	--build-arg R2BOOK_VERSION=$(R2BOOK_VERSION)

.PHONY: all snap docker update clean \
	buildx snap-buildx docker-buildx docker-buildx-tarball \
	docker-buildx-push docker-push-multiarch

# Build both for local arch for testing
all: snap docker

# Build both crossplatform locally for testing
buildx: snap-buildx docker-buildx

# Build docker for local arch for testing
snap:
	docker build $(DOCKER_BUILD_ARGS) \
		--target snap \
		--output "type=local,dest=snaps" \
		docker

# Build docker for local arch for testing
docker:
	docker build $(DOCKER_BUILD_ARGS) $(DOCKER_LABELS) \
		--target docker \
		--tag "$(DOCKER_IMAGE)" \
		docker

# Build crossplatform snap
snap-buildx:
	docker buildx build $(DOCKER_BUILD_ARGS) \
		--platform "$(TARGETPLATFORM)" \
		--target snap \
		--output "type=local,dest=snaps" \
		docker

# Build crossplatform docker locally for testing
docker-buildx:
	docker buildx build $(DOCKER_BUILD_ARGS) $(DOCKER_LABELS) \
		--target docker \
		--platform "$(TARGETPLATFORM)" \
		--output "type=docker" \
		--tag "$(DOCKER_IMAGE)" \
		docker

# Build crossplatform docker as tarball
docker-buildx-tarball:
	mkdir -p docker-images
	docker buildx build $(DOCKER_BUILD_ARGS) $(DOCKER_LABELS) $(DOCKER_ANNOTATIONS_MANIFEST) $(DOCKER_ANNOTATIONS_INDEX) \
		--target docker \
		--platform "$(TARGETPLATFORM)" \
		--attest type=provenance,mode=max \
		--output "type=oci,dest=docker-images/radare2-docker-$(SNAP_ARCH).tar" \
		--tag "$(DOCKER_IMAGE)" \
		docker

# Build and push a single platform image
docker-buildx-push:
	mkdir -p digests
	docker buildx build $(DOCKER_BUILD_ARGS) $(DOCKER_LABELS) $(DOCKER_ANNOTATIONS_MANIFEST) \
		--target docker \
		--platform "$(TARGETPLATFORM)" \
		--iidfile "digests/$(SNAP_ARCH).iidfile" \
		--attest type=provenance,mode=max \
		--output "type=image,name=$(REGISTRY_IMAGE),push-by-digest=true,name-canonical=true,push=true" \
		docker

# digests/%.iidfile:
# 	make docker-buildx-push SNAP_ARCH=$(notdir $(basename $@)) REGISTRY_IMAGE=$(REGISTRY_IMAGE)

# digests: $(addprefix digests/,$(addsuffix .iidfile,$(notdir $(basename $(ARCH_CONFIGS)))))

# Publish image with all iddfile hashes generated by docker-buildx-push
docker-push-multiarch: digests
	docker buildx imagetools create $(DOCKER_ANNOTATIONS_INDEX) \
		--tag "$(REGISTRY_IMAGE):$(DOCKER_TAG)" \
		--tag "$(REGISTRY_IMAGE):$(R2_VERSION)" \
			$(shell awk '{print "$(REGISTRY_IMAGE)@"$$0}' digests/*.iidfile)

# GitHub Actions scripts
update:
	.github/scripts/update-versions.sh
	-git status

# Clean
clean:
	rm -fR snaps digests
