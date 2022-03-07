#!/bin/bash

if [ $RAILS_ENV == "staging "]
then
  bundle exec rake db:create
fi

bundle exec rake db:migrate
bundle exec rails s -b 0.0.0.0