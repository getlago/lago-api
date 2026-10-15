#!/bin/bash
set -e

if [ "$RAILS_ENV" == "staging" ]
then
  bundle exec rake db:prepare
else
  if ! bundle exec rails runner "ActiveRecord::Base.connection.select_value('SELECT 1')" 2>/dev/null; then
    bundle exec rake db:create
  fi
  bundle exec rails db:migrate
  bundle exec rails roles:seed_predefined

  if [ -v LAGO_CREATE_ORG ] && [ "$LAGO_CREATE_ORG" == "true" ]
  then
    bundle exec rails signup:seed_organization
  fi
fi
