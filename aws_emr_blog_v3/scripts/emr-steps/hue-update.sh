#!/bin/bash
set -euo pipefail
set -x
#================================================================
# Updates hive-site.xml permissions (fix for an issue with file permissions)
#================================================================
#% SYNOPSIS
#+    hue-update.sh
#%
#% DESCRIPTION
#%    Fix for an issue with hue is not able to read this file and causes the web UI to not load correctly
#%
#% EXAMPLES
#%    hue-update.sh
#%
#================================================================
#- IMPLEMENTATION
#-    version         hue-update.sh 1.0
#-    author          Varun Bhamidimarri
#-    license         MIT license
#-
#
#================================================================
#================================================================

sudo setfacl -m group:hive_site_reader:r /etc/hive/conf/hive-site.xml
sudo setfacl -m group:hue:r /etc/hive/conf/hive-site.xml

sudo systemctl restart hue
