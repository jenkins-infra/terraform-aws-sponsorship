#!/usr/bin/env bash
set -eux -o pipefail

# This script retrieves addons and AMI version corresponding to a Kubernetes version.

AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_PROFILE="${AWS_PROFILE:-jenkins-infra-admin}"
ADDONS="${ADDONS:-coredns kube-proxy vpc-cni aws-ebs-csi-driver aws-mountpoint-s3-csi-driver eks-pod-identity-agent}"

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 <kubernetes-version>"
  echo "Example: $0 1.34"
  exit 1
fi

k8s_version="$1"

echo "Using Kubernetes version: ${k8s_version}"
echo

get_addon_version() {
  addon_name="$1"

  aws eks describe-addon-versions \
    --kubernetes-version "${k8s_version}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --addon-name "${addon_name}" \
    --query 'addons[0].addonVersions[0].addonVersion' \
    --output text
}

echo "Fetching addon versions..."
for addon in ${ADDONS}; do
  version=$(get_addon_version "${addon}")
  printf "%-35s %s\n" "${addon}:" "${version}"
done

echo "Fetching EKS optimized AMI release version..."
ami_release_version=$(
  aws ssm get-parameters-by-path \
    --path "/aws/service/eks/optimized-ami/${k8s_version}/" \
    --recursive \
    --query "Parameters[?contains(Name, 'amazon-linux-2023/arm64/standard/recommended')].Value" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --output json |
  jq -r '.[0] | fromjson | .release_version'
)

echo "AMI release version: ${ami_release_version}"
