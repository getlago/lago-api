#!/bin/bash

rm -f ./tmp/pids/server.pid
bundle exec rails s -b ::
