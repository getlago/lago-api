#!/bin/bash

./scripts/generate.rsa.sh
./scripts/karafka.web.sh

rm -f ./tmp/pids/server.pid
bundle install

rake db:prepare
bundle exec rails signup:seed_organization
rails s -b 0.0.0.0
