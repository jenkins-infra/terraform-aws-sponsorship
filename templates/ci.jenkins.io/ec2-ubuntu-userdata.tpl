#!/bin/sh
set -eux

## Setup Datadog service
(
    systemctl stop datadog-agent.service
    mkdir -p /var/log/datadog /etc/datadog-agent
    sed 's/api_key:.*/api_key: ${datadog_api_key}/' /etc/datadog-agent/datadog.yaml.example > /etc/datadog-agent/datadog.yaml
    sed -i 's/# site:.*/site: datadoghq.com/' /etc/datadog-agent/datadog.yaml
    echo "tags: [\"jenkins_controller:ci.jenkins.io\", \"jenkins_agent_type:ec2_asg\"]" >> /etc/datadog-agent/datadog.yaml
    chown dd-agent:dd-agent /etc/datadog-agent/datadog.yaml
    chmod 640 /etc/datadog-agent/datadog.yaml
    chown dd-agent:dd-agent /var/log/datadog
    chmod 770 /var/log/datadog
    systemctl daemon-reload
    systemctl enable datadog-agent.service
    systemctl start datadog-agent.service
) 2>&1 | tee /var/log/agent-init-datadog.log

## Setup local NVMe
MNT_DIR="/home/jenkins/agent"

disks=""
tmpfile=$(mktemp)
find -L /dev/disk/by-id/ -xtype l -name '*NVMe_Instance_Storage_*' > "$${tmpfile}"
while IFS= read -r disk; do
    disks="$${disks} $${disk}"
done < "$${tmpfile}"
rm -f "$${tmpfile}"

## Bail early if there are no ephemeral disks to setup
if [ -z "$${disks}" ]; then
    echo "no NVMe instance storage disks found!"
else
    md_name="workspace"
    md_device="/dev/md/$${md_name}"
    md_config="/.aws/mdadm.conf"
    array_mount_point="$${MNT_DIR}/"
    mkdir -p "$(dirname "$${md_config}")"

    ## Get devices of NVMe instance storage ephemeral disks
    EPHEMERAL_DISKS=""
    tmpfile=$(mktemp)
    for disk in $${disks}; do
        realpath "$${disk}"
    done | sort -u > "$${tmpfile}"
    while IFS= read -r disk; do
        EPHEMERAL_DISKS="$${EPHEMERAL_DISKS:+^$EPHEMERAL_DISKS }$${disk}"
    done < "$${tmpfile}"
    rm -f "$${tmpfile}"

    if [ ! -s "$${md_config}" ]; then
        set -- "$${EPHEMERAL_DISKS}"
        num_disks=$#

        mdadm --create --force --verbose \
            "$${md_device}" \
            --level=0 \
            --name="$${md_name}" \
            --raid-devices="$${num_disks}" \
            "$@"

        mdadm --detail --scan > "$${md_config}"
    fi

    # Format the array if not already formatted.
    if [ -z "$(lsblk "$${md_device}" -o fstype --noheadings)" ]; then
        ## By default, mkfs tries to use the stripe unit of the array (512k),
        ## for the log stripe unit, but the max log stripe unit is 256k.
        ## So instead, we use 32k (8 blocks) to avoid a warning of breaching the max.
        ## mkfs.xfs defaults to 32k after logging the warning since the default log buffer size is 32k.
        ## Instances are delivered with disks fully trimmed, so TRIM is skipped at creation time.
        mkfs.xfs -K -l su=8b "$${md_device}"
    fi

    ## Create the mount directory
    mkdir -p "$${array_mount_point}"

    dev_uuid=$(blkid -s UUID -o value "$${md_device}")
    mount_unit_name="$(systemd-escape --path --suffix=mount "$${array_mount_point}")"
    cat > "/etc/systemd/system/$${mount_unit_name}" <<EOF
    [Unit]
    Description=Mount EC2 Instance Store NVMe disk RAID0
    [Mount]
    What=UUID=$${dev_uuid}
    Where=$${array_mount_point}
    Type=xfs
    Options=defaults,noatime
    [Install]
    WantedBy=multi-user.target
EOF
    systemd-analyze verify "$${mount_unit_name}"
    systemctl enable "$${mount_unit_name}" --now
    chown -R jenkins:jenkins "$${array_mount_point}"
fi

## Setup Docker Engine
mkdir -p /etc/docker
cat <<EOF >/etc/docker/daemon.json
{
    "insecure-registries": ["${dockerhub_mirror_hostname}:5000"],
    "registry-mirrors": ["http://${dockerhub_mirror_hostname}:5000"]
}
EOF
systemctl daemon-reload
systemctl restart docker

## Also provide Docker BuildX TOML configuration
cat <<EOF >/etc/buildkitd.toml
debug = true
[registry."docker.io"]
    mirrors = ["${dockerhub_mirror_hostname}:5000"]
    http = true
    insecure = true
EOF

## Setup default java (agent process may use another explicit one)
update-alternatives --install /usr/bin/java java "${java_home}/bin/java" 2000

## Set up custom environment (usually defined on agent templates with EC2/Azure VMs/Kubernetes Jenkins plugins)
## Note: must be performed before jenkins user opens its SSH session so it's picked up by agent.jar process
env_source_file=/etc/profile.d/jenkins-agent
mkdir -p "$(dirname "$${env_source_file}")"
touch "$${env_source_file}"
echo 'export JAVA_HOME=${java_home}' >> "$${env_source_file}"
echo 'export PATH=${java_home}/bin:$PATH' >> "$${env_source_file}"
echo 'export ARTIFACT_CACHING_PROXY_SERVERID=${acp_url}' >> "$${env_source_file}"
# Sanity checks
cat "$${env_source_file}"
. "$${env_source_file}"
env | grep JAVA_HOME

## Retrieve Maven cache from S3 bucket
mkdir -p /cache
aws s3 cp s3://ci-jenkins-io-maven-cache/maven-bom-local-repo.tar.gz /cache/
chown -R root:jenkins /cache

## Mark cloud init as finished using a marker file
mkdir -p "/tmp"
touch "/tmp/.cloud-init.done"
