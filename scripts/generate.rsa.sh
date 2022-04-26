#!/bin/bash

FILE=./.rsa_private.pem

if [ -f "$FILE" ]; then
  echo "RSA Keys already exists"
else
  openssl genrsa -out .rsa_private.pem 2048
  openssl rsa -in .rsa_private.pem -outform PEM -pubout -out .rsa_public.pem
fi
