#!/usr/bin/env bash
set -eux -o pipefail

# This script retrieves addons and AMI release version corresponding to a Kubernetes version.
# If an addon name is passed as (optional) second parameter, it returns its corresponding version only.
# If "ami_release" is passed as (optional) second parameter, it returns the corresponding AMI release version only.

AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_PROFILE="${AWS_PROFILE:-jenkins-infra-admin}"
ADDON_LIST="${ADDON_LIST:-coredns kube-proxy vpc-cni aws-ebs-csi-driver aws-mountpoint-s3-csi-driver eks-pod-identity-agent}"
AMI_TYPE="${AMI_TYPE:-amazon-linux-2023/arm64/standard/recommended}"

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 <kubernetes-version> <addon-name>"
  echo 'Examples:'
  echo "$0 1.34"
  echo "$0 1.34 coredns"
  echo "$0 1.34 ami_release"
  exit 1
fi

k8s_version="$1"
addon_name=''
ami_release_only=false
if [[ "$#" -eq 2 ]]; then
    if [[ "$2" == 'ami_release' ]]; then
        ami_release_only=true
    elif [[ " ${ADDON_LIST} " == *" $2 "* ]]; then
        addon_name="$2"
    else
        echo "Error: the parameter $2 is not recognized as addon or as 'ami_release'"
        exit 1
    fi
fi

# The script can be called with an AWS_ACCESS_KEY_ID set. In that case, we shouldn't pass the profile
profile="--profile ${AWS_PROFILE}"
if [[ -n "${AWS_ACCESS_KEY_ID}" ]]; then
	profile=''
fi

get_addon_version() {
  addon_name="$1"
  # shellcheck disable=SC2086
  aws eks describe-addon-versions \
    --kubernetes-version "${k8s_version}" \
    --region "${AWS_REGION}" \
    --addon-name "${addon_name}" \
    --query 'addons[0].addonVersions[0].addonVersion' \
	--no-cli-pager \
	$profile \
    --output text
}

get_ami_release_version() {
  # shellcheck disable=SC2086
  aws ssm get-parameters-by-path \
	--path "/aws/service/eks/optimized-ami/${k8s_version}/" \
	--recursive \
	--query "Parameters[?contains(Name, '${AMI_TYPE}')].Value" \
	--region "${AWS_REGION}" \
	$profile \
	--output json \
	| jq -r '.[0] | fromjson | .release_version'
}

if [[ -n "${addon_name}" ]]; then
    get_addon_version "${addon_name}"
elif [[ "${ami_release_only}" == true ]]; then
	get_ami_release_version
else
	echo "Fetching addon versions..."
	for addon in ${ADDON_LIST}; do
		version=$(get_addon_version "${addon}")
		printf "%-35s %s\n" "${addon}:" "${version}"
	done

	echo "Fetching EKS optimized AMI release version..."
	ami_release_version=$(get_ami_release_version)

	echo "AMI release version: ${ami_release_version}"
fi
