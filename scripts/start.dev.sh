#!/bin/bash

./scripts/generate.rsa.sh
./scripts/karafka.web.sh

rm -f ./tmp/pids/server.pid
bundle install

rake db:prepare
bundle exec rails signup:seed_organization
bundle exec ./falcon.rb
