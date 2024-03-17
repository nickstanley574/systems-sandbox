# Certificate Automation Script

This script automates the generation of a root Certificate Authority (CA) key and certificate, as well as generating a Certificate Signing Request (CSR) and signing a certificate using the CA key for the System Sandbox Project.

```
nick ~/workspace/systems-sandbox/certificate-authority (master)
$ ./initCA.sh

>>> Init Variables <<<

CA_PASSWORD is purposely not displayed to the user.

Values for certificate fields:
COUNTRY:     US
STATE:       Denial
LOCALITY:    Chicago
ORG:         Systems Sandbox Local

Common name and wildcard domain:
COMMON_NAME: wildcard.sandbox.local
CA_NAME:     wildcard.sandbox.local
DOMAIN:      *.sandbox.local

Paths for CA key and certificate:
CA_KEY:      ca-root-keys/sandboxCA.key
CA_CERT:     certs/sandboxCA.crt

Certificate extension files:
EXTFILE:     ./temp/wildcard.ext
CSRFIE:      ./temp/wildcard.sandbox.local.csr
V3EXT:       ./temp/subjectAltName.ext

>>> Create Root CA private key and Certificate <<<
Issuer: C = US, ST = Denial, L = Chicago, O = Systems Sandbox Local, CN = wildcard.sandbox.local
Not Before: Mar 17 15:07:45 2024 GMT
Not After : Mar 16 15:07:45 2028 GMT

Import certs/sandboxCA.crt into your preferred browser:
   - FireFox: Tools > Options > Advanced > Certificates: View Certificates > Import
   - Chrome: Tools > Privacy and Security > Security > Manage certificates > Import

README: If you choose not to import the Sandbox CA cert, when you access a webpage
signed by the CA, you will get a 'untrusted cert warning.' It is not ideal to get
into the habit of ignoring this warning. It is recommended you import the cert.

Continue? (yes/no)
yes

>>> Generate 'wildcard.sandbox.local' Private Key and Certifican Signing Request (CSR) <<<
./initCA.sh: line 209: -e: command not found

>>> Sign CSR with CA ca-root-keys/sandboxCA.key <<<
Certificate request self-signature ok
subject=CN = wildcard.sandbox.local, C = US, L = Chicago, O = Systems Sandbox Local

>>> Validate Cert <<<
Issuer: C = US, ST = Denial, L = Chicago, O = Systems Sandbox Local, CN = wildcard.sandbox.local
Not Before: Mar 17 15:07:52 2024 GMT
Not After : Mar 17 15:07:52 2025 GMT
DNS:*.sandbox.local
certs/wildcard.sandbox.local.crt: OK
.
├── ca-root-keys
│   └── sandboxCA.key
├── certs
│   ├── sandboxCA.crt
│   ├── wildcard.sandbox.local.crt
│   └── wildcard.sandbox.local.key
├── initCA.sh
├── README.md
└── temp
    ├── subjectAltName.ext
    ├── wildcard.ext
    └── wildcard.sandbox.local.csr

3 directories, 9 files

>>> Done <<<
```

