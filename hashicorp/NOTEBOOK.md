# Hashicorp Notebooks

## Nomad

### Install & Init

- [Cluster Setup | hashicorp.com](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-aws)
- [Learn Nomad Cluster Setup | github.com/hashicorp](https://github.com/hashicorp/learn-nomad-cluster-setup/)
- [My First Nomad Cluster | thekevinwang.com](https://thekevinwang.com/2022/11/20/nomad-cluster)

### Access Control Policies

- [hashicorp.com - Nomad ACL system fundamentals](https://developer.hashicorp.com/nomad/tutorials/access-control/access-control)

    - Tokens - Requests to Nomad are authenticated using a bearer token. Each ACL token has a public Accessor ID which is used to name a token and a Secret ID which is used to make requests to Nomad

    - Policies - Policies consist of a set of rules defining the capabilities or actions to be granted.

    - Rules - Policies are comprised of one or more rules.

    - Capabilities - Capabilities are the set of actions that can be performed.

    - An ACL policy is a named set of rules. Each policy must have a unique name, an optional description, and a rule set. A client ACL token can be associated with multiple policies; a request is allowed if any of the associated policies grant the capability. Management tokens cannot be associated with policies because they are granted all capabilities.

    - The special anonymous policy can be defined to grant capabilities to anonymous requests. An anonymous request is a request made to Nomad without the X-Nomad-Token header specified. This can be used to allow anonymous users to list jobs and view their status, while requiring authenticated requests to submit new jobs or modify existing jobs. By default, there is no anonymous policy set meaning all anonymous requests are denied.

- [hashicorp.com - Bootstrap Nomad ACL system](https://developer.hashicorp.com/nomad/tutorials/access-control/access-control-bootstrap)

    - Once the ACL system is enabled, you need to generate the initial token. This first management token is used to bootstrap the system. **Care should be taken not to lose all of your management tokens. If you do, you will need to re-bootstrap the ACL subsystem.**

    - When the ACL system is enabled, Nomad starts with a default deny-all policy. This means that by default, no permissions are granted

    - The anonymous policy assigns permissions to all unauthenticated requests to Nomad. **We recommend using tokens with specific policies rather than an overly permissive anonymous policy.** This tutorial uses it for illustrative purposes.

    - Once the ACL system is enabled, use the nomad acl bootstrap command: `nomad acl bootstrap`

        - Once the initial bootstrap is performed, it cannot be performed again unless the reset procedure is complete. Make sure to save this AccessorID and SecretID. The bootstrap token is a management type token, meaning it can perform any operation.

        - Save the bootstrap token value to a file named `bootstrap.token`. Replace `BOOTSTRAP_SECRET_ID` with the Secret ID from the bootstrap command.

            - `echo "BOOTSTRAP_SECRET_ID" > bootstrap.token`

            - `export NOMAD_TOKEN=$(cat bootstrap.token)`

            - `nomad status`

    - Install the anonymous policy with the nomad acl policy apply command: `nomad acl policy apply -description "Anonymous policy (full-access)" anonymous anonymous.policy.hcl`

        - Once this command has completed, requests to the cluster that do not present a token will use this policy.

    - You can also use the Nomad API to submit policies as JSON objects.

    - Once you have provided your users with tokens, you can update the anonymous policy to be more restrictive or delete it completely to deny all requests from unauthenticated users.

        - `export NOMAD_TOKEN=$(cat bootstrap.token)`

        - ` nomad acl policy delete anonymous`

    - To enforce client endpoints, you need to enable ACLs on clients as well. Do this by setting the enabled value of the acl stanza to true. Once complete, restart the client to read in the new configuration.

    - After bootstrapping ACLs on the authoritative region, you can create the replication tokens for the non-authoritative regions in a multi-region config. These tokens must be management-type since they communicate with the authoritative region.

        - `nomad acl token create -type="management" -global=true -name="Cluster A Replication Token" -token="c999c4c2-6146-1bac-eb47-3958bbffe9d8"`

    - If all management tokens are lost, it is possible to reset the ACL bootstrap so that it can be performed again. First, you need to determine the reset index with the bootstrap endpoint:

        - `nomad acl bootstrap`
        - `Error bootstrapping: Unexpected response code: 500 (ACL bootstrap already done (reset index: 7))`

        - The error message contains the reset index. To reset the ACL system, create a file named acl-bootstrap-reset containing the value of the "reset index". **This file should be placed in the data directory of the leader node**

        - `echo 7 >> /nomad-data-dir/server/acl-bootstrap-reset`

        - Once the reset file is in place, you can re-bootstrap the cluster: `nomad acl bootstrap`

        - The reset file can be deleted. However, if it is left behind, Nomad will not reset the bootstrap unless the file's contents match the actual reset index.

- [hashicorp.com - Nomad ACL policy concepts](https://developer.hashicorp.com/nomad/tutorials/access-control/access-control-policies)

    - ACL policies are written using HashiCorp Configuration Language (HCL). This language is designed for human readability. The HCL interpreter also parses JSON which facilitates the use of machine-generated configuration.

    - ACL Rules typically have several policy dispositions:

        - read: allow the resource to be read but not modified

        - write: allow the resource to be read and modified

        - deny: do not allow the resource to be read or modified. Deny takes precedence when multiple policies are associated with a token.

        - list: allow the resource to be listed but not inspected in detail. **Applies only to plugins.**

        - Some rules, such as namespace and host_volume, also allow the policy designer to specify a policy in terms of a coarse-grained policy disposition, fine-grained capabilities, or a combination of the two.

    - Nomad allows operators to create multiple namespaces to provide granular access to cluster resources.

        - When no namespace is specified, the "default" namespace is the one used.

        - To grant access to all namespaces, you can use the wildcard namespace (`"*"`)

        - the namespace stanza allows setting a more fine grained list of capabilities. See Nomad ACL policy concepts link fro rull list.

        - Namespace definitions may also include wildcard symbols, also called globs. Namespaces are matched to their rules first by performing a lookup on any exact match, before falling back to performing a glob lookup. When looking up by glob, the matching policy with the greatest number of matched characters will be chosen.

    - The node rule controls access to the Node API such as listing nodes or triggering a node drain.

    - The agent rule controls access to the utility operations in the Agent API, such as join and leave.

    - The operator rule controls access to the Operator API.

    - The quota policy controls access to the quota specification operations in the Quota API, such as quota creation and deletion.

    - The plugin policy controls access to CSI plugins, such as listing plugins or getting plugin status.

    - There's only one [node, agent, operator quota, policy] rule allowed per Nomad ACL Policy, and its value is set to one of the policy dispositions.

    - The host_volume policy controls access to mounting and accessing host volumes.

        - Host volume rules are keyed to the volume names that they apply to. As with namespaces, you may use wildcards to reuse the same configuration.

        -  In addition to the coarse grained policy specification, the host_volume stanza allows setting a more fine grained list of capabilities.

[hashicorp.com - Nomad ACL token fundamentals](https://developer.hashicorp.com/nomad/tutorials/access-control/access-control-tokens)

- Nomad uses tokens to authenticate requests. These tokens are created using`nomad acl token create`. The operator can specify one the policies to apply to the token.

    - You can use the `nomad acl token self` command to get the information about your current token. Remember, you must have the token in the `NOMAD_TOKEN` environment variable. A token contains:

    - Accessor ID - The public identifier for a specific token.

    - Secret ID - Used to make requests to Nomad and **should be kept private** (Like a Private Key)

    - Name (optional) - A user-supplied identifier.

    - Type - Shows the type of the token.

        - Management tokens can perform any action in your cluster. They can not be associated with a policy.

            - `nomad acl token create -name="New Management Token" -type="management"`

            - Management tokens are necessary for working with the Nomad ACL API.

            - You can have as many management tokens as you like. They are revocable at any time by another management token. If you lose all of your management tokens, you will have to re-bootstrap your ACL subsystem.


        - Client tokens are associated with one or more policies when they are created, and can perform an action if any associated policy allows it.

            - `nomad acl token create -name="client1" -policy="app1" -policy="app2"` - It does not matter policies do not yet exist. Nonexistent policies provide no capabilities to a token, they will not cause an error.

            - `nomad acl token create -name="client2" -global -policy="app2` - Generate a global token named "client2" that has access to the app2 policy.

        - You can provide a token for CLI commands in two ways:

            - Use the `-token` flag. Be mindful that flags must come before positional parameters.

            - Set the `NOMAD_TOKEN` environment variable. An advantage of this approach is that you do no longer have to be concerned with argument ordering. `export NOMAD_TOKEN="«Token to use»"`

        - For direct API calls, you will need to supply the token using the `"X-Nomad-Token"` header. This can be paired nicely with the NOMAD_TOKEN environment variable or can be passed directly. `curl --header "X-Nomad-Token: ${NOMAD_TOKEN}" ${NOMAD_ADDR}/v1/jobs`


    - Global - (bool) Indicates whether or not the token was created with the --global flag. Global tokens are replicated from the authoritative region to other connected regions in the cluster.

    - Policies - ([string]) A list of the policies assigned to the token.

    - Create Time - Wall clock time on the Nomad server leader when the token was generated.

    - Create/Modification index - Used by Nomad internally.

    - Sometimes a token needs to be revoked. You can do that by running the `nomad acl token delete`.

[hashicorp.com - Create Nomad ACL policies](https://developer.hashicorp.com/nomad/tutorials/access-control/access-control-create-policy)

- The application developer needs to be able to deploy an application and control its lifecycle. They are allowed to fetch logs from their running containers, but should not be allowed to run commands inside of them or access the filesystem for running workloads.

    -
    ```
    namespace "default" {
        policy       = "read"
        capabilities = ["submit-job","dispatch-job","read-logs"]
    }
    ```

    - `nomad acl token create -name="Test app-dev token" -policy=app-dev -type=client | tee app-dev.token`

- The production operations team needs to be able to perform cluster maintenance and view the workload, including attached resources like volumes, in the running cluster. However, because the application developers are the owners of the running workload, the production operators should not be allowed to run or stop jobs in the cluster.

    -
    ```
    namespace "default" {
        policy = "read"
    }

    node {
        policy = "write"
    }

    agent {
        policy = "write"
    }

    operator {
        policy = "write"
    }

    plugin {
        policy = "list"
    }
    ```

    - `nomad acl token create -name="Test prod-ops token" -policy=prod-ops -type=client | tee prod-ops.token`

- `export NOMAD_TOKEN=$(awk '/Secret/ {print $4}' app-dev.token)`

- Deleting

    - `nomad acl token delete $(awk '/Accessor/ {print $4}' prod-ops.token)`

    - `nomad acl policy delete prod-ops`

- [hashicorp.com - Generate Nomad tokens with HashiCorp Vault](https://developer.hashicorp.com/nomad/tutorials/access-control/vault-nomad-secrets)

    - HashiCorp Vault has a secrets engine for generating short-lived Nomad tokens. As Vault has a number of authentication backends, it could provide a workflow where a user or orchestration system authenticates using an pre-existing identity service (LDAP, Okta, Amazon IAM, etc.) in order to obtain a short-lived Nomad token.

### Securing with TLS

- [hashicorp.com - TLS encryption for Nomad](https://developer.hashicorp.com/nomad/tutorials/transport-security/security-enable-tls)

    - Nomad requires all certificates be signed by the same Certificate Authority (CA). This should be a private CA and not a public one like Let's Encrypt.

    - You can use Nomad to generate the CA's private key and certificate. `nomad tls ca create`. The CA key (`nomad-agent-ca-key.pem`) will be used to sign certificates for Nomad agents and **must be kept private**. The CA certificate (`nomad-agent-ca.pem`) contains the public key necessary to validate Nomad certificates and must be distributed to every node that requires access.

    - TLS certificates commonly use the fully-qualified domain name of the system being identified as the certificate's Common Name (CN). However, hosts (therefore hostnames and IPs) are often ephemeral in Nomad clusters. Not only would signing a new certificate per Nomad node be difficult, but using a hostname provides no security or benefits to Nomad. **Due to this Nomad certificates are signed with their region.**

    - Commands
        - Generate a CA: `nomad tls ca create`
        - Generate a certificate for the Nomad client. `nomad tls cert create -client`
        - Generate a certificate for the CLI: `nomad tls cert create -cli`

    - Each Nomad node should have the appropriate key (`-key.pem`) and certificate (`.pem`) file for its region and role.

    - Each node needs the CA's public certificate (`nomad-agent-ca.pem`).

    - See [nomad.server.hcl](TIODO) and [nomad-client.hcl](TODO) for config comments


### Nginx Reverse Proxy
- [hashicorp.com - NGINX reverse proxy for Nomad's web UI](https://developer.hashicorp.com/nomad/tutorials/manage-clusters/reverse-proxy-ui)

    - NGINX can be used to reverse proxy web services and balance load across multiple instances of the same service. A reverse proxy has the added benefits of enabling multiple web services to share a single, memorable domain and authentication to view internal systems.

    -   ```
        # Nomad blocking queries will remain open for a default of 5 minutes.
        # Increase the proxy timeout to accommodate this timeout with an
        # additional grace period.
        proxy_read_timeout 310s;
        ```

    -   ```
        # Nomad log streaming uses streaming HTTP requests. In order to
        # synchronously stream logs from Nomad to NGINX to the browser
        # proxy buffering needs to be turned off.
        proxy_buffering off;
        ```

    - WebSockets are necessary for the exec API because they allow bidirectional data transfer. This is used to receive changes to the remote output as well as send commands and signals from the browser-based terminal. The way a WebSocket connection is established is through a handshake request. The handshake is an HTTP request with special Connection and Upgrade headers.

    - ```
      # The Upgrade and Connection headers are used to establish
      # a WebSockets connection.
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";  
      # The default Origin header will be the proxy address, which
      # will be rejected by Nomad. It must be rewritten to be the
      # host address instead.
      proxy_set_header Origin "${scheme}://${proxy_host}";
      ```

    - ```
      # Since WebSockets are stateful connections but Nomad has multiple
      # server nodes, an upstream with ip_hash declared is required to ensure
      # that connections are always proxied to the same server node when possible.
      upstream nomad-ws {
      ip_hash;
      server host.docker.internal:4646;
      }
      ```

    - Traffic must also pass through the upstream. To do this, change the proxy_pass in the NGINX configuration file.

- [discuss.hashicorp.com - Accessing Nomad REST API/UI via HTTPS](https://discuss.hashicorp.com/t/accessing-nomad-rest-api-ui-via-https/30812)

- [stackoverflow.com - How to connect to the nomad/consul UI with tls enabled?](https://stackoverflow.com/questions/68421742/how-to-connect-to-the-nomad-consul-ui-with-tls-enabled)

    - [@airo](https://stackoverflow.com/users/1730201/airo) cli keys generated by instruction https://learn.hashicorp.com/tutorials/nomad/security-enable-tls#nomad-ca-key-pem and nginx configured by instruction https://learn.hashicorp.com/tutorials/nomad/reverse-proxy-ui?in=nomad/manage-clusters however this manual does not contain a description of configuring mTLS. You need add following parameters in location /.

    - ```
      location / {
          proxy_ssl_certificate     /etc/nomad.d/cli.pem;
          proxy_ssl_certificate_key /etc/nomad.d/cli-key.pem;
      }
      ```

### Dynamic config generation

- https://stackoverflow.com/questions/77308540/passing-environment-variables-to-nomad-hcl-file-for-making-a-client


## Vault

- [hashicorp.com - Starting the server](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-dev-server)

    - Vault operates as a client-server application. The Vault server is the only piece of the Vault architecture that interacts with the data storage and backends. All operations done via the Vault CLI interact with the server over a TLS connection.

    - `-dev` Enable development mode. In this mode, Vault runs in-memory and starts unsealed. As the name implies, do not run "dev" mode in production. The default is false.

    - **Do not run a Vault dev server in production.**

    - Vault CLI determines which Vault servers to send requests using the VAULT_ADDR environment variable. `export VAULT_ADDR='http://127.0.0.1:8200`

    - Set the VAULT_TOKEN environment variable value to the generated Root Token value displayed in the terminal output. `export VAULT_TOKEN="hvs.XXX"`

    - If you wish to run a Vault dev server with TLS enabled, use the `-dev-tls` flag instead of `-dev`.

        - `export VAULT_CACERT='/var/folders/bz/nvj1yk7j411frmff3198l8_c0000gp/T/vault-tls1123544318/vault-ca.pem'`

- [hashicorp.com - Your first secret](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-first-secret)

    - Secrets written to Vault are encrypted and then written to backend storage. Therefore, the backend storage mechanism never sees the unencrypted value and doesn't have the means necessary to decrypt it without Vault.

    - Use the `vault kv <subcommand> [options] [args]` command to interact with K/V secrets engine.

    - Write a secret: Now, write a key-value secret to the path `hello` , with a key of `foo` and value of `world`, using the `vault kv put` command against the mount path `secret`, which is where the KV v2 secrets engine is mounted. This command creates a new version of the secrets and replaces any pre-existing data at the path if any.

    - `vault kv put -mount=secret hello foo=world`

    - **The examples in this tutorial use the `<key>=<value>` input to send secrets to Vault. However, sending data as a part of the CLI command often end up in the shell history unencrypted. To avoid this, refer to the [Static Secrets: Key/Value Secrets Engine](https://developer.hashicorp.com/vault/tutorials/secrets-management/static-secrets#q-how-do-i-enter-my-secrets-without-exposing-the-secret-in-my-shell-s-history) tutorial to learn different approaches.**

    - Read a secret: `vault kv get -mount=secret hello`.

    - To print only the value of a given field, use the `-field=<key_name>` flag. `vault kv get -mount=secret -field=excited hello`.

    - Optional JSON output is very useful for scripts: `vault kv get -mount=secret -format=json hello | jq -r .data.data.excited`

    - Delete a secret: `vault kv delete -mount=secret hello`

    - ```
      vault kv get -mount=secret hello

      == Secret Path ==
      secret/data/hello

      ======= Metadata =======
      Key                Value
      ---                -----
      created_time       2022-01-15T01:40:09.888293Z
      custom_metadata    <nil>
      deletion_time      2022-01-15T01:40:41.786995Z
      destroyed          false
      version            2
      ```

    - The output only displays the metadata with `deletion_time`. It does not display the data itself once it is deleted. Notice that the `destroyed` parameter is `false` which means that you can recover the deleted data if the deletion was unintentional.

    - `vault kv undelete -mount=secret -versions=2 hello`

    - Other tutorials use the `kv` commands with a different syntax (`vault kv get secret/foo` instead of the `vault kv get -mount=secret foo`). Either will have the same result, but its recommended to use the more explicit `-mount` syntax, it can avoid confusion when you need to refer to the secret by its full path (`secret/data/foo`) when writing policies or raw API calls.

- [hashicorp.com - Secrets engines](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-secrets-engines)

    - Secrets engines are Vault components which store, generate or encrypt secrets.

    - The path prefix (or alternatively the `-mount` flag for `vault kv` commands) tells Vault which secrets engine to which it should route traffic. When a request comes to Vault, it matches the initial path part using a longest prefix match and then passes the request to the corresponding secrets engine enabled at that path. Vault presents these secrets engines similar to a filesystem.

    - Enable a secrets engine: `vault secrets enable -path=kv kv`

    - To verify our success and get more information about the secrets engine, use the vault secrets list command:
      ```
      vault secrets list

      Path          Type         Accessor              Description
      ----          ----         --------              -----------
      cubbyhole/    cubbyhole    cubbyhole_78189996    per-token private secret storage
      identity/     identity     identity_ac07951e     identity store
      kv/           kv           kv_15087625           n/a
      secret/       kv           kv_4b990c45           key/value secret storage
      sys/          system       system_adff0898       system endpoints used for control, policy and debugging
      ```


    -  Vault can interact with more unique environments like AWS IAM, dynamic SQL user creation, etc. all while using the same read/write interface.

    - Vault behaves similarly to a virtual filesystem. The read/write/delete/list operations are forwarded to the corresponding secrets engine, and the secrets engine decides how to react to those operations.

- [hashicorp.com - Dynamic secrets](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-dynamic-secrets)

    - Unlike the kv secrets where you had to put data into the store yourself, dynamic secrets are generated when they are accessed. Dynamic secrets do not exist until they are read, so there is no risk of someone stealing them or another client using the same secrets. Because Vault has built-in revocation mechanisms, dynamic secrets can be revoked immediately after use, minimizing the amount of time the secret existed.

    - Enable the AWS secrets engine: `vault secrets enable -path=aws aws` The AWS secrets engine is now enabled at aws/. Different secrets engines allow for different behavior. In this case, the AWS secrets engine generates dynamic, on-demand AWS access credentials.

    - Your keys must have the IAM permissions listed in the [Vault documentation](https://developer.hashicorp.com/vault/docs/secrets/aws#example-iam-policy-for-vault) to perform the actions on the rest of this page.

    - ```
    vault write aws/config/root \
    access_key=$AWS_ACCESS_KEY_ID \
    secret_key=$AWS_SECRET_ACCESS_KEY \
    region=us-east-1
    ```

    - Vault will automatically revoke this credential after 768 hours (see `lease_duration` in the output), but perhaps you want to revoke it early. Once the secret is revoked, the access keys are no longer valid. To revoke the secret, use `vault lease revoke` with the lease ID that was outputted from `vault read` when you ran it.

- [Authentication](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-authentication)

    - Token authentication is automatically enabled. When you started the dev server, the output displayed a root token. The Vault CLI read the root token from the `VAULT_TOKEN` environment variable. **This root token can perform any operation within Vault because it is assigned the root policy. One capability is to create new tokens.**

    - `vault token create`

    - This token is a child of the root token, and by default, it inherits the policies from its parent.

    - Token is the core authentication method. You can use the generated token to login with Vault, by copy and pasting it when prompted.

    - `vault login`

    - `vault token revoke s.iyNUhq8Ov4hIAx6snw5mB2nL`

    - GitHub authentication:  GitHub authentication enables a user to authenticate with Vault by providing their GitHub credentials and receive a Vault token.

    - `vault auth enable github`

    - This auth method requires that you set a GitHub organization in the configuration. A GitHub organization maintains a list of users which you are allowing to authenticate with Vault.

    - `vault login -method=github`

- [hashicorp.com | Policies](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-policies)

    -   ```
        # Dev servers have version 2 of KV secrets engine mounted by default, so will
        # need these paths to grant permissions:
        path "secret/data/*" {
            capabilities = ["create", "update"]
        }

        path "secret/data/foo" {
            capabilities = ["read"]
        }
        ```

    - With this policy, a user could write any secret to `secret/data/`, except to `secret/data/foo`, where only read access is allowed. Policies default to deny, so any access to an unspecified path is not allowed.

    - There are built-in policies that cannot be removed. The `default` policy provides a common set of permissions and is included on all tokens by default. The `root` policy gives a token super admin permissions.

    - List all the policies: `vault policy list`

    - Upload a policy from stdin: `cat my-policy.hcl | vault policy write my-policy -`

    - View the contents of policy: `vault policy read my-policy`

    - **Associate Policies to Auth Methods** - You can configure auth methods to automatically assign a set of policies to tokens created by authenticating with certain auth methods. The way this is done differs depending on the related auth method, but typically involves mapping a role to policies or mapping identities or groups to policies.

- [hashicorp.com | Deploy Vault](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-deploy)

    - Up to this point, you interacted with the "dev" server, which automatically unseals Vault, sets up in-memory storage, etc. It is important to learn how to deploy Vault into a real environment.

    - Create the Vault configuration in the file `config.hcl`.

    -   ```
        storage "raft" {
            path    = "./vault/data"
            node_id = "node1"
        }

        listener "tcp" {
            address     = "127.0.0.1:8200"
            tls_disable = "true"
        }

        api_addr = "http://127.0.0.1:8200"
        cluster_addr = "https://127.0.0.1:8201"
        ui = true
        ```

    -  As of version 1.12.0, Vault Enterprise will no longer start up if configured to use a storage backend other than Integrated Storage (raft) or Consul (consul). See the Release Notes.

    - Within the configuration file, there are two primary configurations:

        - `storage` - This what Vault uses for storage. The dev server has used in memory, but the example above uses Integrated Storage (raft), a much more production-ready backend.

        - `listener` - One or more listeners determine how Vault listens for API requests. The example above listens on localhost port 8200 without TLS. In your environment set `VAULT_ADDR=http://127.0.0.1:8200` so the Vault client will connect without TLS. **Vault should always use TLS to provide secure communication between clients and the Vault server. It requires a certificate file and key file on each Vault host.**

        - `api_addr` - Specifies the address to advertise to route client requests.

        - `cluster_addr` - Indicates the address and port to be used for communication between the Vault nodes in a cluster.

    - Starting the Server

        - `mkdir -p ./vault/data` - The `./vault/data` directory that `raft` storage backend uses must exist.

        - `vault server -config=config.hcl`

        - **If you get a warning message about mlock not being supported, that is okay. However, for maximum security you should run Vault on a system that supports mlock.** 

    - Initializing the Vault

        - Initialization is the process of configuring Vault. This only happens once when the server is started against a new backend that has never been used with Vault before. **When running in HA mode, this happens once per cluster, not per server.** During initialization, the encryption keys are generated, unseal keys are created, and the initial root token is created.

        -   ```
            export VAULT_ADDR='http://127.0.0.1:8200'

            # This is an unauthenticated request, but it only
            # works on brand new Vaults without existing data.
            vault operator init
            ```

        - Vault initialized with 5 key shares and a key threshold of 3. Please securely distribute the key shares. When the Vault is re-sealed, restarted, or stopped, you must supply at least 3 of these keys to unseal it before it can start servicing requests.

        - Vault does not store the generated root key (previously known as master key). Without at least 3 key to reconstruct the root key, Vault will remain permanently sealed!

        - It is possible to generate new unseal keys, provided you have a quorum of existing unseal keys shares. See "vault operator rekey" for more information.

        -  This is the only time ever that all of this data is known by Vault, and also the only time that the unseal keys should ever be so close together.

        - For the purpose of this getting started tutorial, save all of these keys somewhere, and continue. In a real deployment scenario, you would never save these keys together. Instead, you would likely use Vault's PGP and Keybase.io support to encrypt each of these keys with the users' PGP keys. This prevents one single person from having all the unseal keys. Please see the documentation on using [PGP, GPG, and Keybase](https://developer.hashicorp.com/vault/docs/concepts/pgp-gpg-keybase) for more information.

    - Seal/Unseal

        - Every initialized Vault server starts in the sealed state. The process of teaching Vault how to decrypt the data is known as unsealing the Vault.

        - Unsealing has to happen every time Vault starts. It can be done via the API and via the command line. To unseal the Vault, you must have the threshold number of unseal keys. In the output above, notice that the "key threshold" is 3. This means that to unseal the Vault, you need 3 of the 5 keys that were generated.

        - Begin unsealing the Vault:`vault operator unseal`

        - **Also notice that the unseal process is stateful. You can go to another computer, use vault operator unseal, and as long as it's pointing to the same server, that other computer can continue the unseal process. This is incredibly important to the design of the unseal process: multiple people with multiple keys are required to unseal the Vault. The Vault can be unsealed from multiple computers and the keys should never be together. A single malicious operator does not have enough keys to be malicious.**

        - As a root user, you can reseal the Vault with vault operator seal. A single operator is allowed to do this. This lets a single operator lock down the Vault in an emergency without consulting other operators.

- [hashicorp.com | Using the HTTP APIs with authentication](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-apis)

    - All of Vault's capabilities are accessible via the HTTP API in addition to the CLI. In fact, most calls from the CLI actually invoke the HTTP API. In some cases, Vault features are not available via the CLI and can only be accessed via the HTTP API.

- [hashicorp.com | Vault UI](https://developer.hashicorp.com/vault/tutorials/getting-started/getting-started-ui)

    -  When you operate Vault in development mode the UI is automatically enabled, but when Vault is running outside of development mode, the UI is not activated by default.

    - The UI runs on the same port as the Vault listener. As such, you must configure at least one listener stanza in order to access the UI.

    -   ```
        ui = true

        listener "tcp" {
        address = "10.0.1.35:8200"
        ```

    - In this case, the UI is accessible at the following URL from any machine on the subnet (provided no network firewalls are in place): https://10.0.1.35:8200/ui It is also accessible at any DNS entry that resolves to that IP address, such as the Consul service address (if using Consul): https://vault.service.consul:8200/ui



- [stackoverflow.com- High Available Hashicorp Vault Cluster Installation on VMWare](https://stackoverflow.com/questions/75590758/high-available-hashicorp-vault-cluster-installation-on-vmware) - [ixe013](https://stackoverflow.com/users/591064/ixe013)

    - Keep in mind that with the open source solution, only the primary node will process requests. Other nodes will forward requests they receive to the primary node. OSS Vault also limits your auto-unseal options.

    - For every node you have:

        1. Configure Vault to run as a service on your virtual machine.

        2. Make sure each node can reach its peers on their `cluster_addr` and that they can reach the load-balancer.

        3. All nodes should be configured the same, with Raft storage and the same seal configuration.

        4. Configure your load balancer to poll sys/health so that it always points to the leader node.

        5. Set `VAULT_ADDR` to point to the local node, on each node. Having `VAULT_ADDR=http://localhost:8200` in `/etc/environment` is one way to do that, ymmv.



- [hashicorp.com | Vault with integrated storage reference architecture](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-reference-architecture)

    - Recommended architecture: 5 Vault Servers across 3 AZs behind a LB 1 in active mode 4 in standby

    - With five nodes in the Vault cluster distributed between three availability zones, this architecture can withstand the loss of two nodes from within the cluster or the loss of an entire availability zone.

    - When using Integrated Storage the Vault servers should have a relatively high-performance hard disk subsystem. If many secrets are being generated or rotated frequently, this information will need to flush to disk often and the use of slower storage systems will significantly impact performance.

    - **In addition, Hashicorp strongly recommends configuring Vault with audit logging enabled. The impact of the additional storage I/O from audit logging will vary depending on your particular pattern of requests. For best performance, audit logs should be written to a separate disk.**

    - In order for cluster members to stay properly in sync, network latency between availability zones should be less than eight milliseconds (8 ms).

    - From client machines to the load balancer, and from the load balancer to the Vault servers, standard HTTPS TLS encryption can be used.

    - For communication between Vault servers (port 8201 by default) including Raft gossip, data replication, and request forwarding traffic, Vault automatically negotiates an mTLS connection when new servers join the cluster initially via the API address port (8200 by default).

    - To monitor the health of Vault cluster nodes, the load balancer should be configured to poll the `/v1/sys/health` API endpoint to detect the status of the node and direct traffic accordingly.

    - For scaling the performance of your Vault cluster, there are two factors to consider. Adding additional members to the Vault cluster will not increase performance for any activity that triggers writes to the Vault storage backend. However, for Vault Enterprise customers, adding performance standby nodes can provide horizontal scalability for read requests within a Vault cluster.

    - **Node failure** - The Integrated Storage backend for Vault allows for individual node failure by replicating all data between each node of the cluster. If the leader node fails, the remaining cluster members will elect a new leader following the Raft protocol.

- [hashicorp.com | High availability mode (HA)](https://developer.hashicorp.com/vault/docs/concepts/ha)

    - [High availability parameters](https://developer.hashicorp.com/vault/docs/configuration#high-availability-parameters)

        - `api_addr (string: "")` – Specifies the address (full URL) to advertise to other Vault servers in the cluster for client redirection.

        - `cluster_addr (string: "")` – Specifies the address to advertise to other Vault servers in the cluster for request forwarding.

        - `disable_clustering (bool: false)` – Specifies whether clustering features such as request forwarding are enabled. Setting this to true on one Vault node will disable these features only when that node is the active node. This parameter cannot be set to `true` if `raft` is the storage type.

    - To be highly available, one of the Vault server nodes grabs a lock within the data store. The successful server node then becomes the active node; all other nodes become standby nodes. At this point, if the standby nodes receive a request, they will either forward the request or redirect the client depending on the current configuration and state of the cluster.  Due to this architecture, HA does not enable increased scalability. 

    - Both methods of request handling rely on the active node advertising information about itself to the other nodes.

    - Server-to-Server communication

        - Request forwarding - If request forwarding is enabled (turned on by default in 0.6.2), clients can still force the older/fallback redirection behavior (see below) if desired by setting the X-Vault-No-Request-Forwarding header to any non-empty value.

        - Client redirection

            - If `X-Vault-No-Request-Forwarding` header in the request is set to a non-empty value, the standby nodes will redirect the client using a 307 status code to the active node's redirect address.

            - Some HA data store drivers can autodetect the redirect address, but it is often necessary to configure it manually via a top-level value in the configuration file. The key for this value is api_addr and the value can also be specified by the VAULT_API_ADDR environment variable, which takes precedence.

            - What the api_addr value should be set to depends on how Vault is set up. There are two common scenarios: Vault servers accessed directly by clients, and Vault servers accessed via a load balancer. **In both cases, the api_addr should be a full URL including scheme (http/https), not simply an IP address and port.**

        - Direct access - When clients are able to access Vault directly, the `api_addr` for each node should be that node's address. Then node A would set its api_addr to https://a.vault.mycompany.com:8200 and node B would set its api_addr to https://b.vault.mycompany.com:8200.


    - Behind load balancers

        - Sometimes clients use load balancers as an initial method to access one of the Vault servers, but actually have direct access to each Vault node. In this case, the Vault servers should actually be set up as described in the above section, since for redirection purposes the clients have direct access.

        - However, if the only access to the Vault servers is via the load balancer, the `api_addr` on each node **should be the same**: the address of the load balancer. Clients that reach a standby node will be redirected back to the load balancer; at that point hopefully the load balancer's configuration will have been updated to know the address of the current leader. **This can cause a redirect loop and as such is not a recommended setup when it can be avoided.**

- [hashicorp.com | CLI operator raft](https://developer.hashicorp.com/vault/docs/commands/operator/raft)

    - **If raft is used for `storage`, the node must be joined before unsealing and the `leader-api-addr` argument must be provided.**

    - **If raft is used for `ha_storage`, the node must be first unsealed before joining and the `leader-api-addr` must not be provided.**

    - Params - `-retry` (bool: false) - Continuously retry joining the Raft cluster upon failures. The default is false.


- [blog.yasithab.com | Setup HashiCorp Vault HA Cluster](https://blog.yasithab.com/centos/hashicorp-vault-ha-cluster-with-raft-and-aws-kms-on-centos-7/)
    - NOTE keep alive example



