#!/bin/bash

########################################
# Start cp-demo
########################################

export MONITORING_STACK="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

. $MONITORING_STACK/../utils/setup_cp_demo.sh

echo -e "Launch cp-demo in $CP_DEMO_HOME (version $CP_DEMO_VERSION) and monitoring stack in $MONITORING_STACK"
(cd $CP_DEMO_HOME && ./scripts/start.sh)

source $CP_DEMO_HOME/scripts/helper/functions.sh

########################################
# Start monitoring solution
########################################

echo -e "Create user and certificates for kafkaLagExporter"
KAFKA_LAG_EXPORTER="User:kafkaLagExporter"
SECURITY_DIR="${MONITORING_STACK}/assets/security"
mkdir -p $SECURITY_DIR
(cd $SECURITY_DIR && rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12)
(cd $SECURITY_DIR && $CP_DEMO_HOME/scripts/security/certs-create-per-user.sh kafkaLagExporter)

echo -e "Create role binding for kafkaLagExporter"
cd $CP_DEMO_HOME
KAFKA_CLUSTER_ID=$(docker-compose exec zookeeper zookeeper-shell zookeeper:2181 get /cluster/id 2> /dev/null | grep \"version\" | jq -r .id)
docker-compose exec tools bash -c "confluent iam rolebinding create \
    --principal $KAFKA_LAG_EXPORTER \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID"

echo -e "Launch $MONITORING_STACK"
# docker-compose up -d elasticsearch kibana node-exporter kafka-lag-exporter metricbeat prometheus grafana
docker-compose up -d elasticsearch kibana node-exporter kafka-lag-exporter metricbeat

# Verify Kibana is ready
MAX_WAIT=120
echo
echo -e "\nWaiting up to $MAX_WAIT seconds for Kibana to be ready"
retry $MAX_WAIT host_check_kibana_ready || exit 1
echo -e "\nConfigure Kibana dashboard:"
curl -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -H "securitytenant: global" --form file=@${MONITORING_STACK}/assets/kibana/zookeeper.ndjson
curl -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -H "securitytenant: global" --form file=@${MONITORING_STACK}/assets/kibana/kafka_overview.ndjson
curl -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -H "securitytenant: global" --form file=@${MONITORING_STACK}/assets/kibana/ksqldb_overview.ndjson

echo -e "\nView Kibana dashboards at ->"
echo -e "http://localhost:5601"
