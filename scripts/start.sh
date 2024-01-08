#!/bin/bash

if [ "$RAILS_ENV" == "staging" ]
then
  bundle exec rake db:prepare
fi

rm -f ./tmp/pids/server.pid
bundle exec rails db:migrate:primary

if [ -v LAGO_CLICKHOUSE_ENABLED ] && [ "$LAGO_CLICKHOUSE_ENABLED" == "true" ]
then
  bundle exec rake db:migrate:clickhouse
fi

bundle exec rails signup:seed_organization
bundle exec rails s -b ::
