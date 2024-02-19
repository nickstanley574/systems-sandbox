#/bin/bash
set -xe

nomad_vagrant_ipaddress=$1

# Split the string into an array using commas as the delimiter
IFS=',' read -ra entries <<< "$nomad_vagrant_ipaddress"

# Loop over the entries and append to /etc/hosts
for entry in "${entries[@]}"; do
    IFS='=' read -r hostname ipaddress <<< "$entry"
    echo "$ipaddress $hostname" | sudo tee -a /etc/hosts
done


# Install the required packages.
apt-get update
apt-get install -y gpg coreutils
apt-get install -y nginx


printf "\n\n=== Install Nomad ===\n\n"

# Add the HashiCorp GPG key.
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add the official HashiCorp Linux repository.
GPG_KEY_FILE="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
REPO_URL="https://apt.releases.hashicorp.com"
RELEASE_CODENAME=$(lsb_release -cs)
REPO_LINE="deb [signed-by=${GPG_KEY_FILE}] ${REPO_URL} ${RELEASE_CODENAME} main"
echo "${REPO_LINE}" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update the package index.
apt-get update

# Install the Nomad package.
apt-get install -y nomad

# # Enable autocompletion for Nomad commands.
nomad -autocomplete-install

# Display the installed Nomad version.
nomad --version

# When nomad-cert-creator make the nomad certificates
# then exit 0 out of the init.sh script to allow 
# certs to be copied to host
if [ "$(hostname)" = "nomad-cert-creator" ]; then

    printf "\n=== Create Nomad Certs ===\n\n"

    # Generate a Nomad CA
    # nomad-agent-ca-key.pem - **CA private key. Keep safe.**
    # nomad-agent-ca.pem - CA public certificate.
    nomad tls ca create

    # Generate a certificate for the Nomad server
    # global-server-nomad-key.pem - Nomad server node private key for the `global` region.
    # global-server-nomad.pem - Nomad server node public certificate for the `global` region.
    nomad tls cert create -server -region global -additional-ipaddress 0.0.0.0 -additional-ipaddress 192.168.22.10

    # Generate a certificate for the Nomad client.
    # global-client-nomad-key.pem - Nomad client node private key for the `global` region.
    # global-client-nomad.pem - Nomad client node public certificate for the `global` region.
    nomad tls cert create -client

    # Generate a certificate for the CLI   
    # global-cli-nomad-key.pem - Nomad CLI private key for the `global` region.
    # global-cli-nomad.pem - Nomad CLI certificate for the `global` region.
    nomad tls cert create -cli -additional-dnsname hashistack.vagrant.local

    ls -al

    printf "\n[init.sh] Certificate creations completed.\n"
    exit 0  
fi



printf "\n\n=== Config Nomad ===\n\n"

# Remove existing Nomad configuration files
rm -rf /etc/nomad.d/*

# Move Nomad configuration files to /etc/nomad.d/
mv -v /vagrant/nomad-server.hcl /etc/nomad.d/

# Move nomad certificates to /etc/nomad.d/
mv -v /vagrant/certificates/*.pem /etc/nomad.d/

# Move nomad acl polices to /etc/nomad.d/
mv -v /vagrant/acls /etc/nomad.d/acls

mv -v /vagrant/nomad-cli.env /etc/nomad.d/

# Set ownership to nomad user and group
chown -R nomad:nomad /etc/nomad.d/*

# Adjust permissions
chmod -R 640 /etc/nomad.d/*

ls -al /etc/nomad.d/

# Create an override configuration file for the Nomad service.
# This sets the User and Group for the Nomad service to 'nomad'.
mkdir -p /etc/systemd/system/nomad.service.d/
cat << EOF > /etc/systemd/system/nomad.service.d/override.conf
[Service]
User=nomad
Group=nomad
EOF

systemctl daemon-reload

systemctl enable nomad
systemctl restart nomad

# give nomad time to finshing starting
sleep 3

systemctl status nomad

source /etc/nomad.d/nomad-cli.env

nomad acl bootstrap >> /etc/nomad.d/bootstrap.token

chmod -R 600 /etc/nomad.d/bootstrap.token
chown -R nomad:nomad /etc/nomad.d/bootstrap.token

export NOMAD_TOKEN=$(awk '/Secret/ {print $4}' /etc/nomad.d/bootstrap.token)

nomad acl policy apply -description "Anonymous policy (Read-Only)" anonymous /etc/nomad.d/acls/acl-anonymous.policy.hcl

nomad acl policy apply -description "Developer policy" developer /etc/nomad.d/acls/acl-developer.policy.hcl

nomad acl policy apply -description "Operations policy" platform /etc/nomad.d/acls/acl-platform.policy.hcl



printf "\n\n=== Confiuring Nginx ===\n\n"

mv /vagrant/nginx.conf /etc/nginx/nginx.conf
chown root:root /etc/nginx/nginx.conf
chmod 644 /etc/nginx/nginx.conf

systemctl enable nginx
systemctl restart nginx
systemctl status nginx


