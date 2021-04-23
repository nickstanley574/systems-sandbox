#!/bin/bash

dnf update

dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf install http://rpms.remirepo.net/enterprise/remi-release-8.rpm
dnf module reset php
dnf module enable php:remi-7.3

dnf localinstall http://ltb-project.org/archives/self-service-password-1.3-1.el7.noarch.rpm

dnf install php-mcrypt vim