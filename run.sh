#!/bin/bash

## CONFIG ##
export PAA_HOST="paa.juniper.net"
export PAA_TENANT="paatenant"
export PAA_REGISTER_USER="tenant@user.com"
export PAA_REGISTER_PASS="tesnantpassword"
export PAA_AGENT_NAME="ta-tokyo-1"
export PAA_DATA_PATH="/opt/paa"

export NTP_SERVERS="100.123.0.1"

## MAIN ##
# NTP
apt install -y chrony
mv /etc/chrony/chrony.conf /etc/chrony/chrony.conf.paa_backup
cat /etc/chrony/chrony.conf.paa_backup | sed 's/.*ntp.ubuntu.com/# &/g' | sed 's/.*ubuntu.pool.ntp.org/# &/g' > /etc/chrony/chrony.conf
echo "" >> /etc/chrony/chrony.conf
for srv in $NTP_SERVER; do
	echo "pool $srv iburst" >> /etc/chrony/chrony.conf
done
chown root:root /etc/chrony/chrony.conf
chmod 644 /etc/chrony/chrony.conf
systemctl restart chrony.service
sleep 5
chronyc sources

# Docker (From https://docs.docker.com/engine/install/ubuntu/)
export DEBIAN_FRONTEND=noninteractive
apt remove -y docker docker.io containerd runc
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# PAA
mkdir -p ${PAA_DATA_PATH}
docker pull netrounds/test-agent-application
docker run --network=host --rm -v "${PAA_DATA_PATH}/config":/config netrounds/test-agent-application register --config /config/agent.conf --cc-host=${PAA_HOST} --account=${PAA_TENANT} --email=${PAA_REGISTER_USER} --password=${PAA_REGISTER_PASS}--name=${PAA_AGENT_NAME}

cat <<EOF > "${PAA_DATA_PATH}/docker-compose.yaml"
version: '3.7'
services:
  paata:
    container_name: paata
    image: netrounds/test-agent-application
    restart: always
    network_mode: host
    cap_add:
      - SYS_ADMIN
      - SYS_NICE
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - ${PAA_DATA_PATH}/config:/config
      - /var/run/netns:/var/run/netns
    command: --config /config/agent.conf -A
    logging:
      options:
        max-size: "10m"
        max-file: 3
EOF

cd ${PAA_DATA_PATH}
docker compose up -d
