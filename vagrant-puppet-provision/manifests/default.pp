node default {

  cron { 'puppet_apply':
    command => "for i in {1..3}; do /opt/puppetlabs/bin/puppet apply /etc/puppetlabs/vagrant; sleep 20; done",
    user    => 'root',
    hour    => '*',
    minute  => '*',
  }

  $content = @(EOF)
Welcome to <%= $::fqdn %>!
This system is managed by Puppet.
Changes will be overwritten on next Puppet Agent run.
EOF

  file { '/etc/motd':
    ensure  => file,
    content => inline_epp($content)
  }

  $test_env = @(EOF)
FOOBAR=HELLOWORLD
EOF


  file { '/tmp/test.env':
    ensure  => file,
    content => inline_epp($test_env)
  }

}
