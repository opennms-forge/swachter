#!/bin/bash
set -e
set -o pipefail

usage() {
    cat <<EOM
Usage: ${0##*/} cmd ... [options]

Helper commands for nephron development.

   kafka-purge          purges the flow topic

   flink-cancel <jobId> cancels the given flink job
   flink-list           lists flink jobs
   flink-start          starts the flink cluster
   flink-stop           stops the flink cluster


EOM
}

require_arg () {
    local type="$1"
    local opt="$2"
    local arg="$3"

    if [[ -z "$arg" ]] || [[ "${arg:0:1}" == "-" ]]; then
      die "$opt requires <$type> argument"
    fi
}

KAFKAB=/opt/kafka/bin
FLINKB=/opt/flink/bin

cmd=

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;

        kafka-purge) cmd=t && shift 1
            $KAFKAB/kafka-topics.sh --zookeeper localhost -alter --topic opennms-flows --config retention.ms=1000
            echo "sleep some time..."
            sleep 65s
            $KAFKAB/kafka-topics.sh --zookeeper localhost -alter --topic opennms-flows --config retention.ms=3600000
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
