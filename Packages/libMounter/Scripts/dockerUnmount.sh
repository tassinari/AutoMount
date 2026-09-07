dockerpath=/usr/local/bin/docker
diskutil unmount /Volumes/smbTestShare
$dockerpath rm -f smb-test
builDir=$0
mountDir="$builDir/mount"
if [[ ! -d "$mountDir" ]]; then
  exit 0
fi
rm -rf -- "$mountDir"

