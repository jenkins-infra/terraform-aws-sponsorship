#!/usr/bin/env bash
set -eux -o pipefail

# This script retrieves an AMI release version corresponding to a Kubernetes version passed as parameter.

AWS_PROFILE="${AWS_PROFILE:-}"
kubernetes_version="$1"

# When running locally, you need to set AWS_PROFILE=jenkins-infra-admin
profile=''
if [[ -n "${AWS_PROFILE}" ]]; then
  profile="--profile ${AWS_PROFILE}"
fi

# shellcheck disable=SC2086
version="$(aws ssm get-parameters-by-path \
  --path "/aws/service/eks/optimized-ami/${kubernetes_version}/" \
  --recursive \
  --query "Parameters[?contains(Name, 'amazon-linux-2023/arm64/standard/recommended')].Value" \
  --region us-east-2 \
  ${profile} \
  --output json \
  | jq -r '.[0] | fromjson | .release_version' || true)"

if [[ -z "${version}" ]]; then
	echo "Error: no AMI release version found for Kubernetes ${kubernetes_version}"
	exit 1
fi
echo "${version}"
