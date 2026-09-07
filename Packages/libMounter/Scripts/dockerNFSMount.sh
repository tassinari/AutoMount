#!/bin/bash
dockerpath=/usr/local/bin/docker
builDir=$1
echo "Starting NFS Docker: (dir) $builDir"

# Check if arg 1 is set
if [ -z "$1" ]; then
  echo "arg 1 not set"
  exit 1
fi

# Check if builDir exists and is a directory; if not, create it
if [[ ! -d "$builDir" ]]; then
    mkdir "$builDir"
fi

# Create the testing share directory with test.txt
testingDir="$builDir/testing"
if [[ ! -d "$testingDir" ]]; then
    echo "making $testingDir"
    mkdir "$testingDir"
fi
echo -n "test" > "$testingDir/test.txt"

# Create the test2 share directory
test2Dir="$builDir/test2"
if [[ ! -d "$test2Dir" ]]; then
    echo "making $test2Dir"
    mkdir "$test2Dir"
fi

$dockerpath run -d \
--name nfs-test \
--privileged \
-p 2049:2049 \
-v "$testingDir":/testing \
-v "$test2Dir":/test2 \
-e NFS_EXPORT_0='/testing *(rw,sync,no_subtree_check,no_root_squash,insecure)' \
-e NFS_EXPORT_1='/test2 *(rw,sync,no_subtree_check,no_root_squash,insecure)' \
--restart unless-stopped \
erichough/nfs-server
