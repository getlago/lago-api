#!/bin/bash

if [ "$RAILS_ENV" == "staging" ]
then
  bundle exec rake db:prepare
fi

rm -f ./tmp/pids/server.pid
bundle exec rake db:migrate
bundle exec rails signup:seed_organization
bundle exec rails s -b ::
