.PHONY: bundle-install test-in-docker
RUN_ARGS := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

test:
	RAILS_ENV=test bundle exec rspec $(RUN_ARGS)
test-in-docker:
	DOCKER_BUILDKIT=1 docker build -f Dockerfile.dev -t lagotestcontainer .
	docker run --rm -v $(ROOT_DIR):/app  -e RAILS_ENV=test --entrypoint bundle gembundler:latest exec rspec $(RUN_ARGS)
bundle-install:
	DOCKER_BUILDKIT=1 docker build --no-cache -f Dockerfile.dev -t gembundler .
	docker run --rm -v $(ROOT_DIR):/app  --entrypoint bundle gembundler:latest install
