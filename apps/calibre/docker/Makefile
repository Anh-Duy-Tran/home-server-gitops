.PHONY: build push test

IMAGE ?= ghcr.io/anh-duy-tran/calibre-puller
TAG ?= latest

build:
	docker build -t $(IMAGE):$(TAG) .

push: build
	docker push $(IMAGE):$(TAG)

test:
	docker run --rm $(IMAGE):$(TAG) --help || true

run-dryrun:
	@echo "Testing dry run mode..."
	docker run --rm \
		-e REMOTE_OPDS_URL=https://calibrebooks.dwilliams.cloud/opds \
		-e MAX_BOOKS=5 \
		-e DRY_RUN=1 \
		$(IMAGE):$(TAG)
