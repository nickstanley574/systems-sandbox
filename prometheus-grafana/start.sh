#! /bin/bash
set -xe
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -keyout base_install/_.vagrant.local.key -out base_install/_.vagrant.local.crt -subj "/C=US/ST=Illinois/L=Chicago/O=self-nickstanley574/CN=*.vagrant.local"

# openssl x509 -text -noout -in base_install/_.vagrant.local.crt
vagrant up prometheus grafana
# vagrant up /node*/

# openssl genpkey -algorithm RSA -out key.pem -pkeyopt rsa_keygen_bits:2048
# openssl req -new -key key.pem -days 1096 -extensions v3_ca -batch -out example.csr -utf8 -subj "/C=US/ST=Illinois/L=Chicago/O=self-nickstanley574/CN=*.vagrant.local"
# openssl x509 -req -sha256 -days 3650 -in example.csr -signkey key.pem -set_serial $ANY_INTEGER -extfile openssl.ss.cnf -out example.pem