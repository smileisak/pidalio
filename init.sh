#!/usr/bin/env bash
set -e
source /etc/pidalio.env
/opt/pidalio/kube/kubelet/scripts/download-components.sh
/opt/pidalio/kube/kubelet/scripts/prepare-units.sh
if [[ "${CEPH}" == "True" ]]
then
    /opt/pidalio/kube/kubelet/scripts/ceph/install-ceph-tools.sh
    docker pull ceph/base
fi
docker pull cedbossneo/etcd-cluster-on-docker
export DOCKER_HOST=unix:///var/run/weave/weave.sock
EXISTING_IPS=$(/opt/bin/weave dns-lookup etcd | sort)
EXISTING_IDS=""
echo "Existing IPS: $EXISTING_IPS"
for ip in ${EXISTING_IPS}
do
    echo "Testing $ip"
    curl -s -m 1 http://${ip}:2379/v2/stats/self
    if [ $? -eq 0 ]
    then
        IP_ID=$(curl -s -m 10 http://${ip}:2379/v2/stats/self | jq -r .name | cut -d'-' -f 2)
        EXISTING_IDS=${IP_ID},${EXISTING_IDS}
        echo "Etcd $ip already exist, ID: $IP_ID";
    else
        echo "Etcd $ip did not come up...exiting"
        exit 1
    fi
done
ID="-1"
MAX=$(expr ${ETCD_NODES} - 1)
for id in $(seq 0 ${MAX})
do
    if [[ "$EXISTING_IDS" == *"$id"* ]]
    then
        echo "ID $id already taken";
    else
        ID="${id}"
        break;
    fi
done
if [ "$ID" -eq "-1" ]
then
    echo "Running as proxy"
    docker run --rm --name=etcd-proxy -p 2379:2379 -p 2380:2380 cedbossneo/etcd-cluster-on-docker /bin/etcd_proxy.sh
else
    echo "Using ID: $ID"
    docker run -e ID=${ID} -e FS_PATH=/var/etcd --rm --name=etcd -p 2379:2379 -p 2380:2380 cedbossneo/etcd-cluster-on-docker
fi
