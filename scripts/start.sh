#!/bin/bash

if [ "$RAILS_ENV" == "staging" ]
then
  bundle exec rake db:prepare
fi

rm -f ./tmp/pids/server.pid

if [ -v LAGO_CLICKHOUSE_MIGRATIONS_ENABLED ] && [ "$LAGO_CLICKHOUSE_MIGRATIONS_ENABLED" == "true" ]
then
  bundle exec rails db:migrate:primary
  bundle exec rails db:migrate:clickhouse
else
  bundle exec rails db:migrate
fi

# Must run before signup:seed_organization, which looks the admin role up by
# `admin: true` alone and would otherwise create a Role with a NULL code/name
# and fail the NOT NULL constraint. migrate.sh pairs these two the same way.
bundle exec rails roles:seed_predefined

bundle exec rails signup:seed_organization
exec bundle exec rails s -b ::
