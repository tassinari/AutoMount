#!/bin/bash
dockerpath=/usr/local/bin/docker
builDir=$1
echo "Starting Docker: (dir) $builDir"
# Check if BUILT_PRODUCTS_DIR is set
if [ -z "$1" ]; then
  echo "arg 1 not set"
  exit 1
fi

# Check if builDir exists and is a directory; if not, create it
if [[ ! -d "$builDir" ]]; then
    mkdir "$builDir"
fi

# Create the mount subdirectory
mountDir="$builDir/mount"
if [[ ! -d "$mountDir" ]]; then
    echo "making $mountDir"
    mkdir "$mountDir"
fi

# Create an empty file inside the mount directory
touch "$mountDir/empty_file.txt"
# Create an empty test.txt file

# Reuse the container if it is already there. Several test suites share this one server,
# and `docker run` exits 125 on a name clash, which used to surface as a test failure.
if $dockerpath inspect smb-test >/dev/null 2>&1; then
  echo "smb-test already exists; ensuring it is running"
  $dockerpath unpause smb-test >/dev/null 2>&1
  $dockerpath start smb-test >/dev/null 2>&1
  exit 0
fi

$dockerpath run -d \
--name smb-test \
-p 1445:445 \
-v "$mountDir":/storage \
-e USER=samba \
-e PASS=secret123 \
-e NAME=smbTestShare \
--restart unless-stopped \
dockurr/samba
