#!/usr/bin/env bash
set -eux -o pipefail

# This script retrieves an AWS addon version corresponding to a Kubernetes version.
# It takes the kubernetes version as first parameter, and the addon name as second parameter.

AWS_PROFILE="${AWS_PROFILE:-}"
kubernetes_version="$1"
addon_name="$2"

# When running locally, you need to set AWS_PROFILE=jenkins-infra-admin
profile=''
if [[ -n "${AWS_PROFILE}" ]]; then
  profile="--profile ${AWS_PROFILE}"
fi

# shellcheck disable=SC2086
version="$(aws eks describe-addon-versions \
  --kubernetes-version "${kubernetes_version}" \
  --region us-east-2 \
  --addon-name "${addon_name}" \
  --query 'addons[0].addonVersions[0].addonVersion' \
  --no-cli-pager \
  ${profile} \
  --output text)"

if [[ "${version}" == 'None' ]]; then
	echo "Error: no '${addon_name}' addon version found for Kubernetes ${kubernetes_version}"
	exit 1
fi
echo "${version}"
