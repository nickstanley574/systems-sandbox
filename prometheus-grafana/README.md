# Grafana & Prometheus


## Built w/ Versions
* `Vagrant 2.2.9`
  * `generic/ubuntu1804 (libvirt, 3.0.14)`
* `Prometheus 2.20.0`
* `Node Exporter 1.0.1`
* `Grafana 7.1.1`
* `OpenSSL 1.1.1`

## Goals

* Setup prometheus, grafana and Node Exporter from scratch and play with how these system are used for monitoring a system.
* See how hard it would be to have all grafana dashboard edits done via git managed files and not allow any manual dashboard edits.
* Set system up with security in mind. Use https and basic_auth for Prometheus, Grafana, and Node Exporter connections.


## Resouces Used
* https://serhack.me/articles/monitoring-infrastructure-grafana-influxdb-connectd/
* https://grafana.com/docs/grafana/latest/administration/provisioning/#reusable-dashboard-urls
* https://sysadmins.co.za/setup-prometheus-and-node-exporter-on-linux-for-epic-monitoring/
* https://inuits.eu/blog/prometheus-tls/
* https://prometheus.io/docs/guides/basic-auth/
* https://prometheus.io/docs/prometheus/latest/configuration/configuration/
* https://developer.mozilla.org/en-US/docs/Mozilla/Security/x509_Certificates