#/bin/bash
set -xe

printf "\n[init.sh] Add the official HashiCorp Linux repository"

# Add the HashiCorp GPG key.
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

GPG_KEY_FILE="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
REPO_URL="https://apt.releases.hashicorp.com"
RELEASE_CODENAME=$(lsb_release -cs)
REPO_LINE="deb [signed-by=${GPG_KEY_FILE}] ${REPO_URL} ${RELEASE_CODENAME} main"
echo "${REPO_LINE}" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update the package index.
apt-get update

printf "\n[init.sh] Install Nomad"

# Install the Nomad package.
apt-get install -y nomad

# # Enable autocompletion for Nomad commands.
nomad -autocomplete-install

# Display the installed Nomad version.
nomad --version

# When nomad-cert-creator make the nomad certificates nthen exit 0
# out of the init.sh script to allow certs to be copied to host
if [ "$(hostname)" = "nomad-cert-creator" ]; then

    printf "\n\n[init.sh] Generate Config Assets Nomad Certs\n"

    printf "\n\n[init.sh] Generate a Nomad CA\n"
    # nomad-agent-ca-key.pem - **CA private key. Keep safe.**
    # nomad-agent-ca.pem - CA public certificate.
    nomad tls ca create

    printf "\n\n[init.sh] Generate a Nomad server certificate and private key\n"
    nomad tls cert create -server -region vagrant-local -additional-ipaddress 0.0.0.0 -additional-ipaddress 192.168.22.10

    printf "\n\n[init.sh] Generate Nomad client certificate and private key\n"
    nomad tls cert create -client -region vagrant-local

    printf "\n\n[init.sh] Generate Nomad CLI certificate and private key\n"
    nomad tls cert create -cli -region vagrant-local -additional-dnsname hashistack.vagrant-local

    printf "\n\n[init.sh] Generate hashistack ssh keypair\n"
    ssh-keygen -t rsa -b 2048 -C "hashistack" -f "id_rsa_hashistack"

    printf "\n\n[init.sh] Created Files:\n"
    ls -al

    printf "[init.sh] Done."

    exit 0
fi

# Install the required packages.
apt-get install -y gpg coreutils nginx

printf "\n[init.sh] Create hashistack user"

sudo useradd -m -d /home/hashistack -s /bin/bash hashistack
usermod -aG nomad hashistack
mkdir -p /home/hashistack/.ssh/

mv -v /vagrant/generated_assets/id_rsa_hashistack /home/hashistack/.ssh/id_rsa_hashistack
mv -v /vagrant/generated_assets/id_rsa_hashistack.pub /home/hashistack/.ssh/id_rsa_hashistack.pub

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
mv -v /vagrant/generated_assets/*.pem /etc/nomad.d/

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
sleep 20

systemctl status nomad

# Create Managment Token on Each Nomad Server
if [ "$(hostname)" = "hashistack1" ]; then

    source /etc/nomad.d/nomad-cli.env

    MAX_ATTEMPTS=5      # Maximum number of bootstrap attempts

    for ((attempt=1; i<=$MAX_ATTEMPTS; i++)); do

        # Attempt Nomad ACL bootstrap
        { set +e; nomad acl bootstrap > /etc/nomad.d/bootstrap.token 2>&1; }

        # Check if bootstrap failed due to "No cluster leader" retry if true
        if grep -q "No cluster leader" "/etc/nomad.d/bootstrap.token"; then
            echo "[init.sh] No nomad leader. Retrying ($attempt/$MAX_ATTEMPTS)... "
            sleep 8
        else
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

