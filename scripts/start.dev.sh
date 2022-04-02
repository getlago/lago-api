#!/bin/bash

bundle install
rake db:prepare
rails s -b 0.0.0.0
