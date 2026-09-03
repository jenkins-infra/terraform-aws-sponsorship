#!/usr/bin/env bash
set -eux -o pipefail

# This script retrieves addons and AMI release version corresponding to a Kubernetes version.
# If an addon name is passed as (optional) second parameter, it returns its corresponding version only.
# If "ami_release" is passed as (optional) second parameter, it returns the corresponding AMI release version only.
# When running locally, you need to set AWS_PROFILE=jenkins-infra-admin

get_addon_version() {
  local k8s_version="$1"
  local addon_and_constraint="$2"

  local addon_name="${addon_and_constraint%%:*}"
  local constraint="${addon_and_constraint#*:}"
  local query='addons[0].addonVersions[0].addonVersion'
  if [[ -n "${constraint}" ]]; then
    query="addons[0].addonVersions[?starts_with(addonVersion, '${constraint}')].addonVersion | [0]"
  fi

  # shellcheck disable=SC2086
  aws eks describe-addon-versions \
    --kubernetes-version "${k8s_version}" \
    --region us-east-2 \
    --addon-name "${addon_name}" \
    --query "${query}" \
    --no-cli-pager \
    ${profile} \
    --output text
}

get_ami_release_version() {
  local k8s_version="$1"
  # shellcheck disable=SC2086
  aws ssm get-parameters-by-path \
    --path "/aws/service/eks/optimized-ami/${k8s_version}/" \
    --recursive \
    --query "Parameters[?contains(Name, 'amazon-linux-2023/arm64/standard/recommended')].Value" \
    --region us-east-2 \
    ${profile} \
    --output json \
    | jq -r '.[0] | fromjson | .release_version'
}

# Note the ":v1" to restrict S3-csi-driver to v1.x
ADDON_AND_CONSTRAINT_LIST='aws-ebs-csi-driver: aws-mountpoint-s3-csi-driver:v1. coredns: eks-pod-identity-agent: kube-proxy: vpc-cni:'
AWS_PROFILE="${AWS_PROFILE:-}"

# When running locally, you need to set AWS_PROFILE=jenkins-infra-admin
profile=''
if [[ -n "${AWS_PROFILE}" ]]; then
  profile="--profile ${AWS_PROFILE}"
fi

case "$#" in
  1)
    output='Addon versions: '
    for addon_and_constraint in ${ADDON_AND_CONSTRAINT_LIST}; do
      addon_name="${addon_and_constraint%%:*}"
      version="$(get_addon_version "$1" "${addon_and_constraint}")"
      output+="$(printf "\n%-35s %s\n" "${addon_name}" "${version}")"
    done

    ami_version="$(get_ami_release_version "$1")"
    output+="$(printf '\n\n%-35s %s\n' 'AMI release version:' "${ami_version}")"

    echo "${output}"
    ;;
  2)
    if [[ "$2" == 'ami_release' ]]; then
      get_ami_release_version "$1"
    else
      addon_and_constraint=''
      for item in ${ADDON_AND_CONSTRAINT_LIST}; do
        if [[ "${item%%:*}" == "$2" ]]; then
          addon_and_constraint="${item}"
          break
        fi
      done

      if [[ -n "${addon_and_constraint}" ]]; then
        get_addon_version "$1" "${addon_and_constraint}"
      else
        echo "Error: '$2' is not recognized as an addon or as 'ami_release'"
        exit 1
      fi
    fi
    ;;
  *)
    echo "Usage: $0 <kubernetes-version> <addon-name>"
    echo 'Examples:'
    echo "$0 1.34"
    echo "$0 1.34 coredns"
    echo "$0 1.34 ami_release"
    exit 1
    ;;
esac
