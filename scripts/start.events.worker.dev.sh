#!/bin/bash

bundle install
bin/jobs -c config/queue_events.yml
