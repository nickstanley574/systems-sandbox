#! /bin/bash

openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout node_exporter/node_exporter.key -out node_exporter/node_exporter.crt -subj "/C=US/ST=Illonis/L=Chicago/O=self/CN=*.vagrant.local"

vagrant up prometheus grafana
vagrant up /node*/

echo 'grafana admin/admin: http://localhost:3000'
echo 'prometheus: http://localhost:9090/targets'