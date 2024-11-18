#!/bin/bash

bundle install

bin/jobs -c config/queue.yml
