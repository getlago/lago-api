#!/bin/bash

bundle exec rake db:migrate
bundle exec rails s -b 0.0.0.0