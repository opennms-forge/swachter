#!/bin/bash
set -e
set -o pipefail

get_script_path () {
  local path="$1"
  [[ -L "$path" ]] || { echo "$path" ; return; }

  local -r target="$(readlink "$path")"
  if [[ "${target:0:1}" == "/" ]]; then
    echo "$target"
  else
    echo "${path%/*}/$target"
  fi
}

scriptPath="$(get_script_path "${BASH_SOURCE[0]}")"
SCRIPT_DIR=$(dirname "$scriptPath")
SCRIPT_RES="$SCRIPT_DIR/script-resources"
ES_MAJOR_MINOR=
ES_MAJOR_MINOR_PATCH=

usage() {
    cat <<EOM
Usage: ${0##*/} cmd ... [options]

Helper commands for nephron development.

   es-setup-range-field  setup the range for flow summaries (template, ingest pipeline, and index settings)

   kafka-consumer-groups
   kafka-partitions
   kafka-purge           purges the flow topic
   kafka-offsets

   flink-cancel <jobId>  cancels the given flink job
   flink-list            lists flink jobs
   flink-start           starts the flink cluster
   flink-stop            stops the flink cluster


EOM
}

die () { echo "Aborting: $@" ; exit 1; }

require_arg () {
    local type="$1"
    local opt="$2"
    local arg="$3"

    if [[ -z "$arg" ]] || [[ "${arg:0:1}" == "-" ]]; then
      die "$opt requires <$type> argument"
    fi
}

init_es_version () {
    if [[ -z "$ES_MAJOR_MINOR" ]]; then
        local esn=`curl -s -XGET 'http://localhost:9200' | jq '.version.number'`
        ES_MAJOR_MINOR_PATCH="${esn:1:${#esn}-2}"
        ES_MAJOR_MINOR="${ES_MAJOR_MINOR_PATCH%.*}"
        echo "ElasticSearch version: $ES_MAJOR_MINOR_PATCH"
    fi
}

KAFKAB=/opt/kafka/bin
FLINKB=/opt/flink/bin

cmd=

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;

        es-setup-range-field) cmd=t && shift 1
            init_es_version
            # setup the range field for flow summaries
            # (the range field for raw flows can not be setup similarly because OpenNMS would overwrite the index template)
            echo "put template"
            curl -XPUT -H 'Content-Type: application/json' http://localhost:9200/_template/netflow_agg -d@$SCRIPT_RES/netflow_agg-template.json
            echo
            echo "put pipeline"
            curl -XPUT -H 'Content-Type: application/json' http://localhost:9200/_ingest/pipeline/netflow_agg -d@$SCRIPT_RES/netflow_agg-ingest-pipeline-es-$ES_MAJOR_MINOR.json
            echo
            echo "set default pipeline"
            curl -XPUT -H 'Content-Type: application/json' http://localhost:9200/netflow_agg-*/_settings -d@$SCRIPT_RES/netflow_agg-index.json
            echo
            ;;

        kafka-consumer-groups) cmd=t && shift 1
            $KAFKAB/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe
            ;;

        kafka-delete-topic) cmd=t && shift 1
            $KAFKAB/kafka-topics.sh --zookeeper localhost --delete --topic opennms-flows
            ;;

        kafka-describe-topic) cmd=t && shift 1
            $KAFKAB/kafka-log-dirs.sh --describe --bootstrap-server localhost:9092 --topic-list opennms-flows
            ;;

        kafka-list) cmd=t && shift 1
            $KAFKAB/kafka-topics.sh --list --zookeeper localhost
            ;;

        kafka-purge) cmd=t && shift 1
            $KAFKAB/kafka-topics.sh --zookeeper localhost -alter --topic opennms-flows --config retention.ms=1000
            echo "sleep some time..."
            sleep 65s
            $KAFKAB/kafka-topics.sh --zookeeper localhost -alter --topic opennms-flows --config retention.ms=3600000
            ;;

        kafka-partitions) require_arg "partition count" "$1" "$2" && partitions="$2" && cmd=t && shift 2
            $KAFKAB/kafka-topics.sh --zookeeper localhost -alter --topic opennms-flows --partitions $partitions
            ;;

        kafka-offsets) cmd=t && shift
            $KAFKAB/kafka-run-class.sh kafka.tools.ConsumerOffsetChecker  --zookeeper localhost:2181 --broker-info --group opennms-nephron --topic opennms-flows
            ;;
        flink-cancel) require_arg "job id" "$1" "$2" && jobId="$2" && cmd=t && shift 2
            $FLINKB/flink cancel $jobId
            ;;

        flink-list) cmd=t && shift 1
            $FLINKB/flink list
            ;;

        flink-start) cmd=t && shift 1
            $FLINKB/start-cluster.sh
            ;;

        flink-stop) cmd=t && shift 1
            $FLINKB/stop-cluster.sh
            ;;

        *) echo "unexpected argument: $1" && usage; exit 1 ;;
    esac
done;

if [[ -z "$cmd" ]]; then
    usage
    exit 1
fi
