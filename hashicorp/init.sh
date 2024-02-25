#/bin/bash
set -xe

nomad_vagrant_ipaddress=$1

printf "\n=== Install Nomad ===\n"

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

    printf "\n[init.sh] Generate Config Assets Nomad Certs\n"

    # Generate a Nomad CA
    # nomad-agent-ca-key.pem - **CA private key. Keep safe.**
    # nomad-agent-ca.pem - CA public certificate.
    nomad tls ca create

    # Generate a Nomad server certificate and private key
    # global-server-nomad.pem global-server-nomad-key.pem
    nomad tls cert create -server -region global -additional-ipaddress 0.0.0.0 -additional-ipaddress 192.168.22.10

    # Generate Nomad client certificate and private key
    # global-client-nomad-key.pem  global-client-nomad.pem
    nomad tls cert create -client

    # Generate Nomad CLI certificate and private key
    # global-cli-nomad-key.pem global-cli-nomad.pem
    nomad tls cert create -cli -additional-dnsname hashistack.vagrant.local

    ssh-keygen -t rsa -b 2048 -C "hashistack" -f "id_rsa_hashistack"

    ls -al

    printf "[init.sh] Done."

    exit 0
fi

# Install the required packages.
apt-get install -y gpg coreutils nginx

printf "\n[init.sh] Create hashistack user"

useradd -m --shell /bin/bash hashistack
usermod -aG nomad hashistack

mv -v /vagrant/ssh /home/hashistack/.ssh

cat /home/hashistack/.ssh/id_rsa_hashistack.pub > /home/hashistack/.ssh/authorized_keys

chown -R hashistack:hashistack /home/hashistack/.ssh/ /home/hashistack/.ssh/*
chmod -R 0700 /home/hashistack/.ssh
chmod -R 0600 /home/hashistack/.ssh/*
chmod 644 /home/hashistack/.ssh/*.pub

printf "\n[init.sh] Config Nomad"

# Remove existing Nomad configuration files
rm -rf /etc/nomad.d/*

# Move Nomad configuration files to /etc/nomad.d/
mv -v /vagrant/generated_assets/nomad-server.hcl /etc/nomad.d/

# Move nomad certificates to /etc/nomad.d/
mv -v /vagrant/certificates/*.pem /etc/nomad.d/

mv -v /vagrant/nomad-cli.env /etc/nomad.d/

# Set ownership to nomad user and group
chown -R nomad:nomad /etc/nomad.d/*

# Adjust permissions
chmod  770 /etc/nomad.d/
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

systemctl enable --now nomad

# Give nomad time to finshing starting
sleep 8

systemctl status nomad

# Create Managment Token on Each Nomad Server
if [ "$(hostname)" = "hashistack1" ]; then

    source /etc/nomad.d/nomad-cli.env

    MAX_ATTEMPTS=5      # Maximum number of bootstrap attempts
    SLEEP_DURATION=6    # Sleep duration between retries in seconds

    attempt=1

    while [ $attempt -le $MAX_ATTEMPTS ]; do

        # Attempt Nomad ACL bootstrap
        nomad acl bootstrap > /etc/nomad.d/bootstrap.token 2>&1

        # Check if bootstrap failed due to "No cluster leader" retry if true
        if grep -q "No cluster leader" "/etc/nomad.d/bootstrap.token"; then
            echo "[init.sh] No cluster leader. Retrying in ${SLEEP_DURATION}s (Attempt $attempt/$MAX_ATTEMPTS)"
            sleep $SLEEP_DURATION
        else
            # If no "No cluster leader" is found, assume ACL Bootstrap is complete and break the loop
            echo "[init.sh] Nomad ACL Bootstrap Complete" && break
        fi

        ((attempt++))
    done

    # Check if maximum attempts are reached without success
    [ $attempt -gt $MAX_ATTEMPTS ] && { echo "Maximum number of attempts reached. Exiting with an error."; exit 1; }

    # Set owner and permissions for the bootstrap token file
    chmod -R 600 /etc/nomad.d/bootstrap.token
    chown -R hashistack:hashistack /etc/nomad.d/bootstrap.token

    export NOMAD_TOKEN=$(awk '/Secret/ {print $4}' /etc/nomad.d/bootstrap.token)

    # Get the list of Nomad server members
    nomad_servers=$(nomad server members | awk 'NR>1 {print $1}')

    for s in $nomad_servers; do
        # Add host key to known_hosts file for hashistack user
        sudo -u hashistack bash -c "ssh-keyscan -H $s >> /home/hashistack/.ssh/known_hosts"

        # Copy bootstrap token to remote host for hashistack user using scp
        sudo -u hashistack bash -c "scp -i /home/hashistack/.ssh/id_rsa_hashistack /etc/nomad.d/bootstrap.token hashistack@$s:/etc/nomad.d/bootstrap.token"
    done

    # Move nomad acl polices to /etc/nomad.d/
    mv -v /vagrant/acls /etc/nomad.d/acls

    # Apply Nomad ACL policies
    nomad acl policy apply -description "Anonymous policy (Read-Only)" anonymous /etc/nomad.d/acls/acl-anonymous.policy.hcl
    nomad acl policy apply -description "Developer policy" developer /etc/nomad.d/acls/acl-developer.policy.hcl
fi



printf "\n=== Confiuring Nginx ===\n"

# Move and set permissions for nginx.conf
mv /vagrant/generated_assets/nginx.conf /etc/nginx/nginx.conf
chown root:root /etc/nginx/nginx.conf
chmod 644 /etc/nginx/nginx.conf

systemctl enable --now nginx
systemctl status nginx

