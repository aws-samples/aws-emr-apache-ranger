#!/usr/bin/env bash

echo "***** Install packages required fro AD join *****"
# oddjob oddjob-mkhomedir sssd samba-common-tools gnome-packagekit PackageKit-yum
sudo yum -y install oddjob oddjob-mkhomedir sssd samba-common-tools
