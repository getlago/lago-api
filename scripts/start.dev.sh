#!/bin/bash

rm -f ./tmp/pids/server.pid
bundle install

rake db:prepare
rails s -b 0.0.0.0
