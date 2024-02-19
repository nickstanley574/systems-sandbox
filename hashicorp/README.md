# Hashicorp

**Goal:** Setup a 3 node Nomad, Consul and Vault cluster that will be both a server and agent node. This cluster should be reasonably secure requiring authentication to the clusters and the commination should be secured and the containers service should run not run a root.

**Current State**: Core Nomad TLS secured install completed.

**TODO**
- Split Nomad install into its own script for DRYness
- Enable ACL for Nomad
- Setup Clients
- Consul
- Vault
- Write guide once all above is complete.
- Write install guide
- Add Architecture Diagram
- Add video demo

## Design Overview

In a real prod setup each hashicorp service should be on their own dedicate single purpose cluster and masters should not be clients, clients are meant to be ephemeral since they are meant to dynamically scale. However I do not have a computer that can handle this.

## Versions

- Host
    - Ubuntu XXX
    - Vagrant 2.2.19
    - [Vagrant Libvirt Provider](https://vagrant-libvirt.github.io/vagrant-libvirt/) 0.7.0-1
- Software versions
    - VagrantBox - [generic/ubuntu2204](https://app.vagrantup.com/generic/boxes/ubuntu2204)
    - Nomad - 1.7.4
    - Consul - TBD
    - Vault - TBD
    - Nginx -

Last Verified on

## Install Guide

TODO

### Local Hosts File

## Notes & Resources

### Install & Init
- [Cluster Setup | hashicorp.com](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-aws)
- [Learn Nomad Cluster Setup | github.com/hashicorp](https://github.com/hashicorp/learn-nomad-cluster-setup/)
- [My First Nomad Cluster | thekevinwang.com](https://thekevinwang.com/2022/11/20/nomad-cluster)


**Annoying** - As of Feb 2024 `split()` Doesn't work in `.hcl` files despite `${env.ENV_VAR}` working.


### Securing Nomad

#### ACL

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

#### TLS

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
* https://developer.hashicorp.com/nomad/tutorials/manage-clusters/reverse-proxy-ui
* https://discuss.hashicorp.com/t/accessing-nomad-rest-api-ui-via-https/30812
* https://mpolinowski.github.io/docs/DevOps/Hashicorp/2022-05-24-hashicorp-nomad-with-nginx/2022-05-24/
* https://stackoverflow.com/questions/68421742/how-to-connect-to-the-nomad-consul-ui-with-tls-enabled
