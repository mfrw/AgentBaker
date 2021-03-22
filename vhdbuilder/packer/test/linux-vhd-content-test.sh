#!/bin/bash
git clone https://github.com/Azure/AgentBaker.git 2>/dev/null
source ./AgentBaker/parts/linux/cloud-init/artifacts/ubuntu/cse_install_ubuntu.sh 2>/dev/null
COMPONENTS_FILEPATH=/opt/azure/components.json

testFilesDownloaded() {
  test="testFilesDownloaded"
  echo "$test:Start"
  filesToDownload=$(jq .DownloadFiles[] --monochrome-output --compact-output < $COMPONENTS_FILEPATH)

  for fileToDownload in ${filesToDownload[*]}; do
    fileName=$(echo "${fileToDownload}" | jq .fileName -r)
    downloadLocation=$(echo "${fileToDownload}" | jq .downloadLocation -r)
    versions=$(echo "${fileToDownload}" | jq .versions -r | jq -r ".[]")
    download_URL=$(echo "${fileToDownload}" | jq .downloadURL -r)

    if [ ! -d $downloadLocation ]; then
      err $test "Directory ${downloadLocation} does not exist"
      continue
    fi

    for version in ${versions}; do
      file_Name=$(string_replace $fileName $version)
      dest="$downloadLocation/${file_Name}"
      downloadURL=$(string_replace $download_URL $version)/$file_Name

      if [ ! -s $dest ]; then
        err $test "File ${dest} does not exist"
        continue
      fi

      fileSizeInRepo=$(curl -sI $downloadURL | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
      fileSizeDownloaded=$(wc -c $dest | awk '{print $1}' | tr -d '\r')
      if [[ "$fileSizeInRepo" != "$fileSizeDownloaded" ]]; then
        err $test "File size of ${dest} is invalid. Expected file size: ${fileSizeInRepo} - downlaoded file size: ${fileSizeDownloaded}"
        continue
      fi
    done

    echo "---"
  done
  echo "$test:Finish"
}

testImagesPulled() {
  test="testImagesPulled"
  echo "$test:Start"
  containerRuntime=$1
  if [ $containerRuntime == 'containerd' ]; then
    pulledImages=$(ctr -n k8s.io image ls)
  elif [ $containerRuntime == 'docker' ]; then
    pulledImages=$(docker images --format "{{.Repository}}:{{.Tag}}")
  else
    err $test "unsupported container runtime $containerRuntime"
    return
  fi

  imagesToBePulled=$(echo $2 | jq .ContainerImages[] --monochrome-output --compact-output)

  for imageToBePulled in ${imagesToBePulled[*]}; do
    downloadURL=$(echo "${imageToBePulled}" | jq .downloadURL -r)
    versions=$(echo "${imageToBePulled}" | jq .versions -r | jq -r ".[]")
    for version in ${versions}; do
      download_URL=$(string_replace $downloadURL $version)

      if [[ $pulledImages =~ $downloadURL ]]; then
        echo "Image ${download_URL} has been pulled Successfully"
      else
        err $test "Image ${download_URL} has NOT been pulled"
      fi
    done

    echo "---"
  done
  echo "$test:Finish"
}

testAuditDNotPresent() {
  test="testAuditDNotPresent"
  echo "$test:Start"
  status=$(systemctl show -p SubState --value auditd.service)
  if [ $status == 'dead' ]; then
    echo "AuditD is not present, as expected"
  else
    err $test "AuditD is active with status ${status}"
  fi
  echo "$test:Finish"
}

testChrony() {
  test="testChrony"
  echo "$test:Start"

  # ---- Setup ----
  # TODO remove this installation call once chrony is installed in VHD itself
  disableNtpAndTimesyncdInstallChrony  2>/dev/null

  # ---- Test Setup ----
  # Test ntp is not active
  status=$(systemctl show -p SubState --value ntp)
  if [ $status == 'dead' ]; then
    echo "ntp is removed, as expected"
  else
    err $test "ntp is active with status ${status}"
  fi
  #test chrony is running
  status=$(systemctl show -p SubState --value chrony)
  if [ $status == 'running' ]; then
    echo "chrony is running, as expected"
  else
    err $test "chrony is not running with status ${status}"
  fi

  #test if chrony corrects time
  initialDate=$(date +%s)
  date --set "27 Feb 2021"
  for i in $(seq 1 10); do
    newDate=$(date +%s)
    if (( $newDate > $initialDate)); then
      echo "chrony readjusted the system time correctly"
      break
    fi
    sleep 10
    echo "${i}: retrying: check if chrony modified the time"
  done
  if (($i == 10)); then
    err $test "chrony failed to readjust the system time"
  fi
  echo "$test:Finish"
}

testFips() {
  test="testFips"
  echo "$test:Start"
  os_version=$1
  enable_fips=$2

  if [[ ${os_version} == "18.04" && ${enable_fips,,} == "true" ]]; then
    kernel=$(uname -r)
    if [[ -f /proc/sys/crypto/fips_enabled ]]; then
        echo "FIPS is enabled."
    else
        err $test "FIPS is not enabled."
    fi

    if [[ -f /usr/src/linux-headers-${kernel}/Makefile ]]; then
        echo "fips header files exist."
    else
        err $test "fips header files don't exist."
    fi
  fi

  echo "$test:Finish"
}

testKubeBinariesPresent() {
  test="testKubeBinaries"
  echo "$test:Start"
  containerRuntime=$1
  binaryDir=/usr/local/bin
  k8sVersions="
  1.17.3-hotfix.20200601.1
  1.17.7-hotfix.20200817.1
  1.17.9-hotfix.20200824.1
  1.17.11-hotfix.20200901.1
  1.17.13
  1.17.16
  1.18.2-hotfix.20200624.1
  1.18.4-hotfix.20200626.1
  1.18.6-hotfix.20200723.1
  1.18.8-hotfix.20200924
  1.18.10-hotfix.20210118
  1.18.14-hotfix.20210118
  1.19.0
  1.19.1-hotfix.20200923
  1.19.3
  1.19.6-hotfix.20210118
  1.19.7-hotfix.20210122
  1.20.2
  "
  for patchedK8sVersion in ${k8sVersions}; do
    # Only need to store k8s components >= 1.19 for containerd VHDs
    if (($(echo ${patchedK8sVersion} | cut -d"." -f2) < 19)) && [[ ${containerRuntime} == "containerd" ]]; then
      continue
    fi
    # strip the last .1 as that is for base image patch for hyperkube
    if grep -iq hotfix <<< ${patchedK8sVersion}; then
      # shellcheck disable=SC2006
      patchedK8sVersion=`echo ${patchedK8sVersion} | cut -d"." -f1,2,3,4`;
    else
      patchedK8sVersion=`echo ${patchedK8sVersion} | cut -d"." -f1,2,3`;
    fi
    k8sVersion=$(echo ${patchedK8sVersion} | cut -d"_" -f1 | cut -d"-" -f1 | cut -d"." -f1,2,3)
    kubeletLocation="$binaryDir/kubelet-$k8sVersion"
    kubectlLocation="$binaryDir/kubectl-$k8sVersion"
    if [ ! -s $kubeletLocation ]; then
      err $test "Binary ${kubeletLocation} does not exist"
    fi
    if [ ! -s $kubectlLocation ]; then
      err $test "Binary ${kubectlLocation} does not exist"
    fi
  done
  echo "$test:Finish"
}

testKubeProxyImagesPulled() {
  test="testKubeProxyImagesPulled"
  echo "$test:Start"
  containerRuntime=$1
  dockerKubeProxyImages='
{
  "ContainerImages": [
    {
      "downloadURL": "mcr.microsoft.com/oss/kubernetes/kube-proxy:v*",
      "versions": [
        "1.17.3-hotfix.20200601",
        "1.17.7-hotfix.20200714",
        "1.17.9-hotfix.20200824",
        "1.17.11-hotfix.20200901",
        "1.17.13",
        "1.17.16",
        "1.18.4-hotfix.20200626",
        "1.18.6-hotfix.20200723",
        "1.18.8-hotfix.20200924",
        "1.18.10-hotfix.20210118",
        "1.18.14-hotfix.20210118",
        "1.19.0",
        "1.19.1-hotfix.20200923",
        "1.19.3",
        "1.19.6-hotfix.20210118",
        "1.19.7-hotfix.20210122",
        "1.20.2"
      ]
    }
  ]
}
'
containerdKubeProxyImages='
{
  "ContainerImages": [
    {
      "downloadURL": "mcr.microsoft.com/oss/kubernetes/kube-proxy:v*",
      "versions": [
        "1.19.0",
        "1.19.1-hotfix.20200923",
        "1.19.3",
        "1.19.6-hotfix.20210118",
        "1.19.7-hotfix.20210122",
        "1.20.2"
      ]
    }
  ]
}
'
  if [ $containerRuntime == 'containerd' ]; then
    testImagesPulled containerd "$containerdKubeProxyImages"
  elif [ $containerRuntime == 'docker' ]; then
    testImagesPulled docker "$dockerKubeProxyImages"
  else
    err $test "unsupported container runtime $containerRuntime"
    return
  fi
  echo "$test:Finish"
}

err() {
  echo "$1:Error: $2" >>/dev/stderr
}

string_replace() {
  echo ${1//\*/$2}
}

testFilesDownloaded
testImagesPulled $1 "$(cat $COMPONENTS_FILEPATH)"
testChrony
testAuditDNotPresent
testFips $2 $3
testKubeBinariesPresent $1
testKubeProxyImagesPulled $1
