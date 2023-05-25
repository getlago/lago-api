#!/bin/bash

./scripts/generate.rsa.sh

rm -f ./tmp/pids/server.pid
bundle install

rake db:prepare
rake graphql:schema:dump
bundle exec rails signup:seed_organization
rails s -b 0.0.0.0
