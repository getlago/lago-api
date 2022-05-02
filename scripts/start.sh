#!/bin/bash

if [ "$RAILS_ENV" == "staging" ]
then
  bundle exec rake db:create
  bundle exec rake db:migrate
  bundle exec rake db:seed
fi

rm -f ./tmp/pids/server.pid
bundle exec rake db:migrate
bundle exec rails s -b 0.0.0.0