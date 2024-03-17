#!/bin/bash

set -e

###############################################################################
#
# This script automates the the generation of a root Certificate Authority (CA)
# key and certificate, as well as generating a Certificate Signing Request (CSR)
# and signing a certificate using the CA key for the System Sandbox Project.
#
# Main Referance:
# https://www.ibm.com/docs/en/runbook-automation?topic=certificate-generate-root-ca-key
#
###############################################################################


# Function to display usage instructions
display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --recreate    Re create the CA this will overwrite the existing files."
    echo "  --help        Display this help message"
    exit 0
}


log() {
    printf "\n>>> $1 <<<\n"
}


# Set default values
recreate_flag=false

# Parse command-line options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --recreate)
            recreate_flag=true
            shift
            ;;
        --help)
            display_help
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done



###############################################################################
# Init Variables
###############################################################################

log "Init Variables"

# Generate CA password; CA_PASSWORD is purposely not displayed to the user.
# This CA is meant only to be used by the system sandbox project. Once the
# certs are created, they should not be needed again. If, for whatever reason,
# there is an issue with the certs, the cert can be regenerated with --recreate.

printf "\nCA_PASSWORD is purposely not displayed to the user.\n"
export CA_PASSWORD=$(openssl rand -base64 15 | tr -d '/+=' | cut -c1-15)


# Set default values for certificate fields
COUNTRY=US
STATE=Denial
LOCALITY=Chicago
ORG="Systems Sandbox Local"

printf "\nValues for certificate fields:\n"
echo "COUNTRY:     $COUNTRY"
echo "STATE:       $STATE"
echo "LOCALITY:    $LOCALITY"
echo "ORG:         $ORG"


# Define common name and wildcard domain
COMMON_NAME=wildcard.sandbox.local
CA_NAME=$COMMON_NAME
DOMAIN='*.sandbox.local'

printf "\nCommon name and wildcard domain:\n"
echo "COMMON_NAME: $COMMON_NAME"
echo "CA_NAME:     $CA_NAME"
echo "DOMAIN:      $DOMAIN"


# Define paths for CA key and certificate
CA_KEY=ca-root-keys/sandboxCA.key
CA_CERT=certs/sandboxCA.crt

printf "\nPaths for CA key and certificate:\n"
echo "CA_KEY:      $CA_KEY"
echo "CA_CERT:     $CA_CERT"


# Define paths for certificate extension files
EXTFILE=./temp/wildcard.ext
CSRFIE=./temp/$CA_NAME.csr
V3EXT='./temp/subjectAltName.ext'

printf "\nCertificate extension files:\n"
echo "EXTFILE:     $EXTFILE"
echo "CSRFIE:      $CSRFIE"
echo "V3EXT:       $V3EXT"


# Checks if the CA key file exists. If it does, further checks if the recreate flag is set.
if [ -f "$CA_KEY" ]; then
    # If recreate flag is set, deletes current CA and certificates.
    if $recreate_flag; then
        printf "\n\nWARN: Recreate CA, deleting current CA and certs\n\n"
        rm -rf certs/* temp/* ca-root-keys/*
    # If recreate flag is not set, show info about the --recreate flag and exit.
    else
        printf "\nThere is already Sandbox CA. If you would like to ovewrite the current\n"
        printf "CA files and certs run the script with the --recreate flag set.\n\n"
        exit 1
    fi
fi



###############################################################################
# Create Root CA private key and Certificate
###############################################################################

log "Create Root CA private key and Certificate"

openssl genrsa -out $CA_KEY -passout env:CA_PASSWORD 2048

# Valid for 4 Years
openssl req \
    -x509 \
    -sha256 \
    -new \
    -nodes \
    -days 1460 \
    -passin env:CA_PASSWORD \
    -key  $CA_KEY \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORG/CN=$COMMON_NAME" \
    -out $CA_CERT

openssl x509 -text -noout -in $CA_CERT | grep -e "GMT" -e "Issuer" | sed 's/^[ \t]*//'

printf "\nImport $CA_CERT into your preferred browser:\n"
printf "   - FireFox: Tools > Options > Advanced > Certificates: View Certificates > Import\n"
printf "   - Chrome: Tools > Privacy and Security > Security > Manage certificates > Import\n"
printf "\n"
printf "README: If you choose not to import the Sandbox CA cert, when you access a webpage\n"
printf "signed by the CA, you will get a 'untrusted cert warning.' It is not ideal to get\n"
printf "into the habit of ignoring this warning. It is recommended you import the cert.\n\n"

valid_input=false
while [ "$valid_input" != true ]; do
    # Prompt the user
    echo "Continue? (yes/no)"

    # Read user input
    read answer

    # Check the input
    if [[ $answer == "yes" ]]; then
        valid_input=true
    elif [[ $answer == "no" ]]; then
        valid_input=true
        exit 0
    else
        echo "Invalid input. Please enter 'yes' or 'no'."
    fi
done


###############################################################################
# Generate COMMON_NAME private key and Certifican Signing Request (CSR)
###############################################################################

log "Generate '$COMMON_NAME' Private Key and Certifican Signing Request (CSR)"

# Generate a new RSA private key with 2048-bit length and save it to a file
openssl genrsa -out certs/$CA_NAME.key 2048

# Create a temporary configuration file for OpenSSL to use
cat > $EXTFILE << EOF
[req]
req_extensions = v3_req
distinguished_name = dn
prompt = no

[dn]
commonName = $COMMON_NAME
countryName = $COUNTRY
localityName = $LOCALITY
organizationName = $ORG

[v3_req]
subjectAltName = DNS:$DOMAIN
EOF

openssl req -new -key certs/$CA_NAME.key -sha256 -config $EXTFILE -out $CSRFIE

# Extract and display the DNS information from the CSR
openssl req -in $CSRFIE -noout -text | grep -e DNS -e GMT -e "Issuer" | sed 's/^[ \t]*//'



###############################################################################
# Sign CSR with CA Private Key
###############################################################################

log "Sign CSR with CA $CA_KEY"

cat > $V3EXT << EOF
subjectAltName = DNS:$DOMAIN
EOF

# Instead of sending the csr to a "legitimate" certificate
# authority we will sign it with our private key
# Valid for 1 year
openssl x509 -req \
    -in $CSRFIE \
    -out certs/$CA_NAME.crt \
    -CA $CA_CERT \
    -CAkey $CA_KEY \
    -days 365 \
    -passin env:CA_PASSWORD \
    -extfile $V3EXT



###############################################################################
# Validate Cert
###############################################################################

log "Validate Cert"

openssl x509 -text -noout -in  certs/$CA_NAME.crt | grep -e DNS -e GMT -e "Issuer" | sed 's/^[ \t]*//'

openssl verify -CAfile $CA_CERT certs/$CA_NAME.crt

tree .

log "Done"
