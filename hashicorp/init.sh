#/bin/bash
set -xe

nomad_vagrant_ipaddress=$1

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

# When nomad-cert-creator make the nomad certificates nthen exit 0
# out of the init.sh script to allow certs to be copied to host
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

    printf "\n[init.sh] Certificate creations completed.\n"

    ssh-keygen -t rsa -b 2048 -C "hashistack" -f "id_rsa_hashistack"

    ls -al

    exit 0
fi


printf "\n\n===== Create hashistack User =====\n\n"

useradd -m --shell /bin/bash hashistack
usermod -aG nomad hashistack

mv -v /vagrant/ssh /home/hashistack/.ssh

cat /home/hashistack/.ssh/id_rsa_hashistack.pub > /home/hashistack/.ssh/authorized_keys

chown -R hashistack:hashistack /home/hashistack/.ssh/ /home/hashistack/.ssh/*

chmod -R 0700 /home/hashistack/.ssh
chmod -R 0600 /home/hashistack/.ssh/*
chmod 644 /home/hashistack/.ssh/*.pub


printf "\n\n===== Config Nomad =====\n\n"

# Remove existing Nomad configuration files
rm -rf /etc/nomad.d/*

# Move Nomad configuration files to /etc/nomad.d/
mv -v /vagrant/nomad-server.hcl /etc/nomad.d/

# Move nomad certificates to /etc/nomad.d/
mv -v /vagrant/certificates/*.pem /etc/nomad.d/

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
sleep 8

systemctl status nomad

# Create Managment Token on Each Nomad Server
if [ "$(hostname)" = "hashistack1" ]; then

    source /etc/nomad.d/nomad-cli.env

    MAX_ATTEMPTS=9

    SLEEP_DURATION=10

    for ((attempt=1; attempt<=$MAX_ATTEMPTS; attempt++)); do

        nomad acl bootstrap > /etc/nomad.d/bootstrap.token 2>&1

        if grep -q "response code: 500 (No cluster leader)" "/etc/nomad.d/bootstrap.token"; then
            echo "No cluster leader. Retrying in ${SLEEP_DURATION}s (Attempt $attempt/$MAX_ATTEMPTS)"
            sleep $SLEEP_DURATION
        elif [ $attempt -eq $MAX_ATTEMPTS ]; then
            echo "Maximum number of attempts reached. Exiting with an error."
            exit 1
        else
            echo "Nomad ACL Bootstap Complete"
            break
        fi
    done

    chmod -R 600 /etc/nomad.d/bootstrap.token
    chown -R nomad:nomad /etc/nomad.d/bootstrap.token


    # Move nomad acl polices to /etc/nomad.d/
    mv -v /vagrant/acls /etc/nomad.d/acls

    export NOMAD_TOKEN=$(awk '/Secret/ {print $4}' /etc/nomad.d/bootstrap.token)
    nomad acl policy apply -description "Anonymous policy (Read-Only)" anonymous /etc/nomad.d/acls/acl-anonymous.policy.hcl
    nomad acl policy apply -description "Developer policy" developer /etc/nomad.d/acls/acl-developer.policy.hcl
fi



printf "\n\n=== Confiuring Nginx ===\n\n"

mv /vagrant/nginx.conf /etc/nginx/nginx.conf
chown root:root /etc/nginx/nginx.conf
chmod 644 /etc/nginx/nginx.conf

systemctl enable nginx
systemctl restart nginx
systemctl status nginx


