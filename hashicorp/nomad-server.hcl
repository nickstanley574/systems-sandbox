# Leader config file
datacenter = "vagrant"
data_dir   = "/opt/nomad/data"
bind_addr  = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 1

  server_join {
    retry_join = [
      "hashistack1.global",
      "hashistack2.global",
      "hashistack3.global",
    ]

    # Every 15 seconds try to connect to cluster
    # max try 20 resulting in 20min of attempts
    retry_max      = 20
    retry_interval = "15s"
  }
}

tls {

    # Enable TLS for HTTP and RPC protocols. Nomad doesn't use separate ports for
    # TLS and non-TLS traffic: your cluster should either use TLS or not.

    http = true
    rpc  = true

    ca_file   = "/etc/nomad.d/nomad-agent-ca.pem"
    cert_file = "/etc/nomad.d/global-server-nomad.pem"
    key_file  = "/etc/nomad.d/global-server-nomad-key.pem"


    # If verify_server_hostname is set to false, the node's certificate will be
    # checked to ensure it is signed by the same CA, but its role and region
    # will not be verified. This means any service with a certificate signed by
    # the same CA as Nomad can act as a client or server of any region.

    verify_server_hostname = true
    verify_https_client    = true
}

ui {
  enabled = true
  label {
      text             = "Local Vagrant Clusters"
      background_color = "yellow"
      text_color       = "#000000"
    }
}

// acl {
//   enabled = true
// }
