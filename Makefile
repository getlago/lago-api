.PHONY: bundle-install test-in-docker migrate-tests-in-docker
RUN_ARGS := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

test:
	RAILS_ENV=test bundle exec rspec $(RUN_ARGS)
test-in-docker:
	docker compose -f docker-compose.test.yml run --rm unittest -- $(RUN_ARGS)
migrate-tests-in-docker:
	docker compose -f docker-compose.test.yml run --rm migrate
bundle-install:
	DOCKER_BUILDKIT=1 docker build --no-cache -f Dockerfile.dev -t gembundler .
	docker run --rm -v $(ROOT_DIR):/app  --entrypoint bundle gembundler:latest install
