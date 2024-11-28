#!/bin/bash

bundle install
bin/jobs -c config/queue.yml --recurring-schedule-file=config/recurring.yml
