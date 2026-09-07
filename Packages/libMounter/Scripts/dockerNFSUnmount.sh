dockerpath=/usr/local/bin/docker
diskutil unmount /Volumes/testing
diskutil unmount /Volumes/test2
$dockerpath rm -f nfs-test
builDir=$0
testingDir="$builDir/testing"
test2Dir="$builDir/test2"
if [[ -d "$testingDir" ]]; then
  rm -rf -- "$testingDir"
fi
if [[ -d "$test2Dir" ]]; then
  rm -rf -- "$test2Dir"
fi
