#! /usr/bin/env bash

mkdir -p $HOME/.ssh

curl -s https://api.github.com/users/mounta11n/keys | jq -r '.[].key' >> $HOME/.ssh/authorized_keys

echo 'nice'
