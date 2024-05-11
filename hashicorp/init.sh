#/bin/bash
set -xe

printf "\n[init.sh] Move wildcard.standbox.local certs to /usr/share/ca-certificates\n\n"

ls -al /certs

mv /certs/ /usr/share/ca-certificates/systems-sandbox

chown root:root /usr/share/ca-certificates/systems-sandbox/
chown root:root /usr/share/ca-certificates/systems-sandbox/*
chmod 755 /usr/share/ca-certificates/systems-sandbox
chmod 644 /usr/share/ca-certificates/systems-sandbox/*



printf "\n\n[init.sh] Add the official HashiCorp Linux repository\n\n"

# Add the HashiCorp GPG key.
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

GPG_KEY_FILE="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
REPO_URL="https://apt.releases.hashicorp.com"
RELEASE_CODENAME=$(lsb_release -cs)
REPO_LINE="deb [signed-by=${GPG_KEY_FILE}] ${REPO_URL} ${RELEASE_CODENAME} main"
echo "${REPO_LINE}" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update the package index.
apt-get -qq update



printf "\n\n[init.sh] Install Nomad\n\n"

# Install the Nomad package.
apt-get install -y nomad

# # Enable autocompletion for Nomad commands.
nomad -autocomplete-install

# Display the installed Nomad version.
nomad --version



# When nomad-cert-creator make the nomad certificates nthen exit 0
# out of the init.sh script to allow certs to be copied to host
if [ "$(hostname)" = "nomad-cert-creator" ]; then

    DOMAIN="sandbox.local"

    printf "\n\n[init.sh] Generate Config Assets Nomad Certs\n\n"

    printf "\n\n[init.sh] Generate a Nomad CA\n\n"
    # nomad-agent-ca-key.pem - **CA private key. Keep safe.**
    # nomad-agent-ca.pem - CA public certificate.
    nomad tls ca create

    printf "\n\n[init.sh] Generate a Nomad server certificate and private key\n\n"
    nomad tls cert create -server -region local -additional-ipaddress 0.0.0.0 -additional-ipaddress 192.168.22.10

    printf "\n\n[init.sh] Generate Nomad client certificate and private key\n\n"
    nomad tls cert create -client -region local

    printf "\n\n[init.sh] Generate Nomad CLI certificate and private key\n\n"
    nomad tls cert create -cli -region local -additional-dnsname hashistack.$DOMAIN

    printf "\n\n[init.sh] Generate hashistack ssh keypair\n\n"
    ssh-keygen -t rsa -b 2048 -C "hashistack" -f "id_rsa_hashistack"

    printf "\n\n[init.sh] Created Files:\n\n"
    ls -al

    printf "\n[init.sh] Done.\n"

    exit 0
fi



# Install the required packages.
apt-get -qq install -y gpg coreutils nginx jq

printf "\n\n[init.sh] Create hashistack user\n\n"

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
sleep 10

journalctl -u nomad --lines=12

systemctl status nomad



# Create Managment Token on Each Nomad Server
if [ "$(hostname)" = "hashistack1" ]; then

    source /etc/nomad.d/nomad-cli.env

    MAX_ATTEMPTS=5      # Maximum number of bootstrap attempts

    for ((attempt=1; attempt<=$MAX_ATTEMPTS; attempt++)); do

        # Attempt Nomad ACL bootstrap
        { set +e; nomad acl bootstrap > /etc/nomad.d/bootstrap.token 2>&1; }

        # Check if bootstrap failed due to "No cluster leader" retry if true
        if grep -q "No cluster leader" "/etc/nomad.d/bootstrap.token"; then
            echo "[init.sh] No nomad leader. Retrying ($attempt/$MAX_ATTEMPTS)... "
            sleep 5
        else
            echo "[init.sh] Nomad ACL Bootstrap Complete" && break
        fi

    done

    # Check if maximum attempts are reached without success
    [ $attempt -gt $MAX_ATTEMPTS ] && { echo "Maximum number of attempts reached. Exiting with an error."; exit 1; }

    # Set owner and permissions for the bootstrap token file
    chmod -R 600 /etc/nomad.d/bootstrap.token
    chown -R hashistack:hashistack /etc/nomad.d/bootstrap.token

    export NOMAD_TOKEN=$(awk '/Secret/ {print $4}' /etc/nomad.d/bootstrap.token)

    # Get the list of Nomad server members
    nomad_servers=$(nomad server members | awk 'NR>1 {print $1}')

    for host in $nomad_servers; do

        # Add host key to known_hosts file for hashistack user
        sudo -u hashistack bash -c "ssh-keyscan -H $host >> /home/hashistack/.ssh/known_hosts"

        # Copy bootstrap token to remote host for hashistack user using scp
        sudo -u hashistack bash -c "scp -i /home/hashistack/.ssh/id_rsa_hashistack /etc/nomad.d/bootstrap.token hashistack@$host:/etc/nomad.d/bootstrap.token"

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

systemctl enable nginx
systemctl restart nginx

sleep 5

journalctl -u nginx --lines=12

systemctl status nginx



######################################
#####       Install Vault        #####
######################################

current_host=$(hostname)

printf "\n\n[init.sh] Config Vault\n\n"

export VAULT_CACERT='/usr/share/ca-certificates/systems-sandbox/sandboxCA.crt'
export VAULT_DIR=/etc/vault.d

VAULT_CONFIG_FILE=$VAULT_DIR/vault.hcl
UNSEAL_FILE=/etc/vault.d/unseal_keys.json

apt-get -qq install -y vault

vault -autocomplete-install

mkdir $VAULT_DIR/acls
mv -v /vagrant/acls-vault/* /etc/vault.d/acls/
mv /vagrant/generated_assets/vault-$current_host.hcl $VAULT_CONFIG_FILE

export VAULT_ADDR=$(grep -w api_addr.* $VAULT_CONFIG_FILE | awk -F '"' '{print $2}' | tr -d '\n')

chown -R vault:vault $VAULT_DIR/*
chmod -R 640 $VAULT_DIR/*

systemctl enable --now vault.service
sleep 10 # Give vault a little time to start

if [ "$(hostname)" = "hashistack1" ]; then

    neighbor_servers_addresses=$(grep leader_api_addr $VAULT_CONFIG_FILE | awk -F '"' '{print $2}' | tr '\n' ' ')

    for address in $neighbor_servers_addresses; do

        max_attempts=5
        attempt=0

        while [ $attempt -lt $max_attempts ]; do

            attempt=$((attempt + 1))

            response=$(curl -sSL --cacert $VAULT_CACERT -o /dev/null -w "%{http_code}" -I "$address/v1/sys/health")

            # https://developer.hashicorp.com/vault/api-docs/system/health - 501 if not initialized (But running)
            [[ "$response" == "501" ]] && break

            echo "Attempt $attempt/$max_attempts: Vault is not yet ready, waiting..."

            # If the attempt count is less than max attempts,sleep; else, exit.
            [ $attempt -lt $max_attempts ] && sleep 5 || { echo "Max attempts reached."; exit 1; }
        done

    done

    vault operator init -key-shares=1 -key-threshold=1 -format=json > $UNSEAL_FILE

    chmod -R 400 $UNSEAL_FILE

    export VAULT_TOKEN=$(jq -r '.root_token' "$UNSEAL_FILE")

    unseal_keys_hex=$(jq -r '.unseal_keys_hex[0]' "$UNSEAL_FILE")

    vault operator unseal $unseal_keys_hex

    # Avoid 'Vault is not initialized' error
    sleep 10

    for address in $neighbor_servers_addresses; do
        curl -s --cacert $VAULT_CACERT -X PUT --data "{\"key\": \"$unseal_keys_hex\"}" $address/v1/sys/unseal
    done

    sleep 30

    vault operator raft list-peers

    # Create Admin Token

    vault policy write admin /etc/vault.d/acls/vault-acl-admin.policy.hcl

    admin_policy_token=$(vault token create -policy=admin -format=json -period=120m | jq -r .auth.client_token)

    # Show all needed tokens to user
    set +x; sleep 2 # Prevent the output from being out of order

    printf "\n\n\n"
    printf "TOKENS\n"
    printf "¯¯¯¯¯¯\n\n"

    printf "vault admin_policy token: $admin_policy_token\n\n"
    printf "vault root token:         $VAULT_TOKEN\n\n"
    printf "nomad bootstrap token:    $NOMAD_TOKEN\n\n"

    printf "\n\nDone.\n\n"


fi
