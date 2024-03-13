.PHONY: bundle-install
RUN_ARGS := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

test:
	RAILS_ENV=test bundle exec rspec $(RUN_ARGS)
bundle-install:
	DOCKER_BUILDKIT=1 docker build --no-cache -f Dockerfile.dev -t gembundler .
	docker run --rm -v $(ROOT_DIR):/app  --entrypoint bundle gembundler:latest install
