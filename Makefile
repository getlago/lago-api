RUN_ARGS := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))

test:
	RAILS_ENV=test bundle exec rspec $(RUN_ARGS)
