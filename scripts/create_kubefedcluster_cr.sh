#!/usr/bin/env bash

user_help () {
    echo "Creates KubeFedCluster"
    echo "options:"
    echo "-t, --type            joining cluster type (host or member)"
    echo "-mn, --member-ns      namespace where member-operator is running"
    echo "-hn, --host-ns        namespace where host-operator is running"
    exit 0
}

if [[ $# -lt 6 ]]
then
    user_help
fi

while test $# -gt 0; do
       case "$1" in
            -h|--help)
                user_help
                ;;
            -t|--type)
                shift
                JOINING_CLUSTER_TYPE=$1
                shift
                ;;
            -mn|--member-ns)
                shift
                if test $# -gt 0; then
                    MEMBER_OPERATOR_NS=$1
                    INSTALL_SPECIFIC_VERSION="1"
                else
                    echo "Member Operator Namespace is not specified."
                    exit 1
                fi
                shift
                ;;
            -hn|--host-ns)
                shift
                if test $# -gt 0; then
                    HOST_OPERATOR_NS=$1
                else
                    echo "Host Operator Namespace is not specified."
                    exit 1
                fi
                shift
                ;;
            *)
               echo "$1 is not a recognized flag!"
               user_help
               exit -1
               ;;
      esac
done


echo "Joining Cluster Type: ${JOINING_CLUSTER_TYPE}"
echo "Member Operator Namespace: ${MEMBER_OPERATOR_NS}"
echo "Host Operator Namespace: ${HOST_OPERATOR_NS}"

SA_NAME=${JOINING_CLUSTER_TYPE}"-operator"

# find ns to get secret and create reference secret
CLUSTER_JOIN_TO="host"
NS_TO_GET_SECRET="${MEMBER_OPERATOR_NS}"
NS_TO_CREATE_SECRET="${HOST_OPERATOR_NS}"
if [[ ${JOINING_CLUSTER_TYPE} == "host" ]]; then
  CLUSTER_JOIN_TO="member"
  NS_TO_GET_SECRET="${HOST_OPERATOR_NS}"
  NS_TO_CREATE_SECRET="${MEMBER_OPERATOR_NS}"
fi

# getting sa with required secrets and certs
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

# create secret reference on the cluster
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