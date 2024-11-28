#!/bin/bash

bundle install
bin/jobs -c config/queue_pdfs.yml
