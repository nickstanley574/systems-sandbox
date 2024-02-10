#/bin/bash
set -x

vm_vagrant_address=$1
nomad_vagrant_ipaddress=$2

# Split the string into an array using commas as the delimiter
IFS=',' read -ra entries <<< "$nomad_vagrant_ipaddress"

# Loop over the entries and append to /etc/hosts
for entry in "${entries[@]}"; do
    IFS='=' read -r hostname ipaddress <<< "$entry"
    echo "$ipaddress $hostname" | sudo tee -a /etc/hosts
done

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
apt-get install -y nginx
apt-get install -y nomad

# consul vault

nomad -autocomplete-install

#consul -autocomplete-install
#vault -autocomplete-install

printf "\n=== Apt Installs Done ===\n\n"

nomad --version
#consul --version
#vault --version

printf "\n=== Configuring Nomad ===\n\n"

rm -rf /etc/nomad.d/*
mv -v /tmp/nomad.d/* /etc/nomad.d/

chown -R nomad:nomad /etc/nomad.d/*
chmod -R 640 /etc/nomad.d/*

# chown -R nomad:nomad /opt/nomad/*

echo "VAGRANT_IPADDRES=$vm_vagrant_address" >> /etc/environment

mkdir -p /etc/systemd/system/nomad.service.d/
cat << EOF > /etc/systemd/system/nomad.service.d/override.conf
[Service]
User=nomad
Group=nomad
EOF

printf "\n\n=== Confiuring nginx ===\n\n"
mv /tmp/nginx/nginx.conf /etc/nginx/nginx.conf
chown root:root /etc/nginx/nginx.conf
chmod 644 /etc/nginx/nginx.conf

systemctl enable nginx
systemctl restart nginx
systemctl status nginx

printf "\n\n=== Starting Nomad ===\n\n"

systemctl enable nomad
systemctl restart nomad
systemctl status nomad

# Give time for all instance to start and connect
sleep 6

# printf "\n\nnomad-ui: https://$vm_vagrant_address:4646/ui/\n\n"

