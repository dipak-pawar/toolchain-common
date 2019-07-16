#!/usr/bin/env bash


JOINING_CLUSTER_TYPE=$1
MEMBER_OPERATOR_NS=${MEMBER_NS:toolchain-member-operator}
HOST_OPERATOR_NS=${HOST_NS:toolchain-host-operator}
SA_NAME=${JOINING_CLUSTER_TYPE}"-operator"

echo "Member Operator Namespace: ${MEMBER_OPERATOR_NS}"
echo "Host Operator Namespace: ${HOST_OPERATOR_NS}"

CLUSTER_JOIN_TO="host"
NS_TO_GET_SECRET="${MEMBER_OPERATOR_NS}"
NS_TO_CREATE_SECRET="${HOST_OPERATOR_NS}"
if [[ ${JOINING_CLUSTER_TYPE} == "host" ]]; then
  CLUSTER_JOIN_TO="member"
  NS_TO_GET_SECRET="${HOST_OPERATOR_NS}"
  NS_TO_CREATE_SECRET="${MEMBER_OPERATOR_NS}"
fi

echo "Switching to project ${NS_TO_GET_SECRET}"
oc project "${NS_TO_GET_SECRET}"

echo "Getting SA token from ${JOINING_CLUSTER_TYPE} cluster"
SA_TOKEN=`oc sa get-token ${SA_NAME}`
SA_SECRET=`oc get sa ${SA_NAME} -o json | jq -r .secrets[].name | grep token`
SA_CA_CRT=`oc get secret ${SA_SECRET} -o json | jq -r '.data["ca.crt"]'`

# infrastructure CRD is only available in Opeshift 4.x
API_ENDPOINT=`oc get infrastructure cluster --template={{.status.apiServerURL}}`
JOINING_CLUSTER_NAME=`oc get infrastructure cluster --template={{.status.infrastructureName}}`

echo "Switching to project ${NS_TO_CREATE_SECRET}"
oc project "${NS_TO_CREATE_SECRET}"

CLUSTER_JOIN_TO_NAME=`oc get infrastructure cluster --template={{.status.infrastructureName}}`
oc create secret generic ${SA_NAME}-${JOINING_CLUSTER_NAME} --from-literal=token="${SA_TOKEN}" --from-literal=ca.crt="${SA_CA_CRT}"

KUBEFEDCLUSTER_CR="apiVersion: core.kubefed.k8s.io/v1beta1
kind: KubeFedCluster
metadata:
  name: ${JOINING_CLUSTER_TYPE}-${JOINING_CLUSTER_NAME}
  namespace: ${NS_TO_CREATE_SECRET}
  labels:
    type: ${JOINING_CLUSTER_TYPE}
    namespace: ${NS_TO_CREATE_SECRET}
    ownerClusterName: ${CLUSTER_JOIN_TO}-${CLUSTER_JOIN_TO_NAME}
spec:
  apiEndpoint: ${API_ENDPOINT}
  caBundle: ${SA_CA_CRT}
  secretRef:
    name: ${SA_NAME}-${JOINING_CLUSTER_NAME}
"

echo "Creating KubeFedCluster representation of ${JOINING_CLUSTER_TYPE} in ${CLUSTER_JOIN_TO}:"
echo ${KUBEFEDCLUSTER_CR}

cat <<EOF | oc apply -f -
${KUBEFEDCLUSTER_CR}
EOF
