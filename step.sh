#!/bin/bash

set -e

#
# Init
provisioning_profile_dir="${HOME}/Library/MobileDevice/Provisioning Profiles"
temp_dir="${HOME}/tmp_dir"

#
# Required parameters
if [ -z "${certificate_url}" ] ; then
  echo "Missing required input: certificate_url"
  exit 1
fi

if [ -z "${keychain_path}" ] ; then
  echo "Missing required input: keychain_path"
  exit 1
fi

if [ -z "${keychain_password}" ] ; then
  echo "Missing required input: keychain_password"
  exit 1
fi

if [ -z "${provisioning_profile_url}" ] ; then
  echo "Missing required input: provisioning_profile_url"
  exit 1
fi

if [ -z "${provisioning_profile_dir}" ] ; then
  echo "Missing required input: provisioning_profile_dir"
  exit 1
else
  mkdir -p "${provisioning_profile_dir}"
fi

if [ -z "${temp_dir}" ] ; then
  echo "Missing required input: temp_dir"
  exit 1
else
  mkdir -p "${temp_dir}"
fi

#
# Download certificate and profile
function download_file {
  local path="$1"
  local url="$2"

  set +e

  curl -Lfso "${path}" "${url}"
  local result=$?

  if [ ${result} -ne 0 ]; then
    echo " (i) Failed to download, retrying..."
    sleep 5
    curl -Lfso "${path}" "${url}"
    local result=$?
    if [ ${result} -ne 0 ]; then
      path=""
    fi
  fi

  if [[ ! -f "${path}" ]]; then
    echo "Failed to download from: ${url}"
    exit 1
  fi

  set -e
}

certificate_path="${temp_dir}/Certificate.p12"

if [ -z "${certificate_local_path}" ] ; then
  echo "Using local certificate"
  cp "${certificate_local_path}" "${certificate_path}"
else  
  echo "Downloading certificate"
  download_file "${certificate_path}" "${certificate_url}"
fi

#
# Install certificate

if [ ! -f "${keychain_path}" ] ; then
  echo "=> Creating keychain: ${keychain_path}"
  security -v create-keychain -p "${keychain_password}" "${keychain_path}"
else
  echo "=> Keychain already exists, using it: ${keychain_path}"
fi

security -v import "${certificate_path}" -k "${keychain_path}" -P "${certificate_passphrase}" -A
security -v set-keychain-settings -lut 72000 "${keychain_path}"
security -v list-keychains -s $(security -v list-keychains | tr -d '"') "${keychain_path}"
security -v default-keychain -s "${keychain_path}"
security -v unlock-keychain -p "${keychain_password}" "${keychain_path}"

certificate_identity=$(security find-certificate -a ${keychain_path} | grep -Ei '"labl"<blob>=".*"' | grep -oEi '=".*"' | grep -oEi '[^="]+' | grep -i '^iPhone' | head -n 1)
echo "Installed certificate: $certificate_identity"
printf "${certificate_identity}" | envman add --key 'BITRISE_CODE_SIGN_IDENTITY'
echo

#
# Install provisioning profiles
#  NOTE: the URL can be a pipe (|) separated list of Provisioning Profile URLs

if [ -z "${provisioning_profile_local_path}" ] ; then
  IFS='|' read -a profiles <<< "${provisioning_profile_local_path}"
else
  IFS='|' read -a profiles <<< "${provisioning_profile_url}"
fi


profile_count="${#profiles[@]}"
echo " (i) Provided Provisioning Profile count: ${profile_count}"
for idx in "${!profiles[@]}"
do
  profile_url="${profiles[idx]}"

  tmp_path="${temp_dir}/profile-${idx}.mobileprovision"
  if [ -z "${provisioning_profile_local_path}" ] ; then
    echo "Downloading provisioning profile: ${idx+1}/${profile_count}"
    download_file "${tmp_path}" "${profile_url}"
  else
    echo "Copy provisioning profile: ${idx+1}/${profile_count}"
    cp "${profile_url}" "${tmp_path}"
  fi
  
  echo "Installing provisioning profile"
  profile_uuid=$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< $(/usr/bin/security cms -D -i "${tmp_path}"))
  echo "=> Installed Profile UUID: ${profile_uuid}"
  mv "${tmp_path}" "${provisioning_profile_dir}/${profile_uuid}.mobileprovision"

  if [[ "${profile_count}" == "1" ]] ; then
    # export it
    printf "${profile_uuid}" | envman add --key 'BITRISE_PROVISIONING_PROFILE_ID'
  fi
done

if [[ "${profile_count}" != "1" ]] ; then
  echo " (!) Won't export BITRISE_PROVISIONING_PROFILE_ID, only a single profile id can be exported and ${profile_count} specified!"
fi

echo
echo "==> DONE"
