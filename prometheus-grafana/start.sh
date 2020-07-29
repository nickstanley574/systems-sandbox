#! /bin/bash
set -xe
# openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -keyout base_install/_.vagrant.local.key -out base_install/_.vagrant.local.crt -subj "/C=US/ST=Illinois/L=Chicago/O=self-nickstanley574/CN=*.vagrant.local"

# openssl x509 -text -noout -in base_install/_.vagrant.local.crt

# vagrant up prometheus grafana
# vagrant up /node*/
