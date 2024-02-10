#/bin/bash
set -xe

# Install the required packages.
apt-get update
apt-get install wget gpg coreutils

# Add the HashiCorp GPG key.
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add the official HashiCorp Linux repository.
GPG_KEY_FILE="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
REPO_URL="https://apt.releases.hashicorp.com"
RELEASE_CODENAME=$(lsb_release -cs)
REPO_LINE="deb [signed-by=${GPG_KEY_FILE}] ${REPO_URL} ${RELEASE_CODENAME} main"

echo "${REPO_LINE}" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install.
apt-get update
apt-get install nomad

nomad -autocomplete-install

printf "\n=== Apt Installs Done ===\n\n"

nomad --version

printf "\n=== Create Nomad Certs ===\n\n"

pwd 

nomad tls ca create
nomad tls cert create -server -region global -additional-ipaddress 0.0.0.0 -additional-ipaddress 192.168.22.10
nomad tls cert create -client
nomad tls cert create -cli -additional-dnsname hashistack.vagrant.local

ls -al