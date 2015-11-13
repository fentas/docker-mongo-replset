#!/bin/bash

#
# COMMANDS
#
curl=/usr/bin/curl
jq=/usr/bin/jq
dig=/usr/bin/dig
mongo=/usr/bin/mongo
cronexpr=/usr/bin/cronexpr

#
# ENVIRONMENT
#
__MONGO_REPLSET=${MONGO_REPLSET:-rs0}
__VERBOSE=${VERBOSE:-6}
__META_URL=${META_URL:-"http://rancher-metadata/2015-07-25"}
__SERVICE=${SERVICE:-mongo-replset}
__HOST_LABEL=${HOST_LABEL:-mongo}
__INTERVAL=${INTERVAL:-30}
__MAINTENANCE=${MAINTENANCE:-@daily}
__PORT=${PORT:-27017}
if [ ! -z "${AUTHENTICATION}" ]; then
  __AUTHENTICATION=(-u ${AUTHENTICATION//:*/} -p ${AUTHENTICATION//*:/} --authenticationDatabase 'admin')
fi
#
# GLOBALS
#
__CURRENT_IPS=""
__RECONFIG=false
declare -A __ROLES
declare -A __PRIORITY
__PRIORITY=(["primary"]=2 ["secondary"]=1 ["arbiter"]=0 ["hidden"]=0)

#
# FUNCTIONS
#
declare -A LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="crit" [3]="err" [4]="warning" [5]="notice" [6]="info" [7]="debug")
function .log () {
  local LEVEL=${1}
  shift
  if [ ${__VERBOSE} -ge ${LEVEL} ]; then
    echo "[${LOG_LEVELS[$LEVEL]}]" "$@"
  fi
}

function .join { local IFS="$1"; shift; echo "$*"; }

function .in_array {
  local KEY=$1
  shift
  local VALUES=$@
  for entry in ${VALUES} ; do
    if [ "${KEY}" == "$entry" ]; then
      return 0
    fi
  done
  return 1
}

function .reconfig {
  local FORCE=${1}
  local PRIMARY=${2}
  .log 6 "Reconfig primary (${PRIMARY} - force: ${FORCE})"

  ID=0
  MEMBERS=()
  for IP in ${__CURRENT_IPS} ; do
    EXTRA=""
    case ${__ROLES[$IP]} in
      "arbiter")
        EXTRA+=", \"arbiterOnly\": true"
        ;;
      "hidden")
        EXTRA+=", \"hidden\": true"
        ;;
    esac
    PRIORITY=${__PRIORITY[${__ROLES[$IP]}]}
    MEMBERS+=("{ \"_id\": ${ID}, \"host\":\"${IP}:${__PORT}\", \"priority\": ${PRIORITY}${EXTRA} }")
    ID=$((${ID} + 1))
  done
  CONFIG=$(echo "{ \"_id\": \"${__MONGO_REPLSET}\", \"members\": [ $(.join , "${MEMBERS[@]}") ]}" | $jq -c .)
  .log 6 ${CONFIG}

  case $(echo "rs.status()" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet | $jq -r '.code') in
    94)
      .log 5 "Status code: 94 - Needs to be initiated."
      # { "info" : "run rs.initiate(...) if not yet done for the set", "ok" : 0, "errmsg" : "no replset config has been received", "code" : 94 }
      echo "if ( rs.initiate().ok ) rs.reconfig(${CONFIG}, { force: ${FORCE} })" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet
      ;;
    *)
      .log 7 "Rs status code: ${1}"
      .log 6 $(echo "rs.reconfig(${CONFIG}, { force: ${FORCE} })" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet)
      ;;
  esac
}

function .peers_check {
  local PRIMARY=${1}
  # Cluster configured, sync host list via primary
  CONFIGURED_IPS=$(echo "rs.conf()" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet | $jq .members[].host | sed 's/\"\([^:]*\):\([^:]*\)\"/\1/g')
  .log 7 "Configured ips: ${CONFIGURED_IPS[@]}"

  # build additions list
  NEW_IPS=()
  for IP in ${__CURRENT_IPS}; do
    if ! .in_array ${IP} ${CONFIGURED_IPS}; then
      NEW_IPS+=(${IP})
    fi
  done
  if [ ! -z "${NEW_IPS[@]}" ]; then .log 6 "New ips: ${NEW_IPS[@]}"; fi

  for IP in ${NEW_IPS}; do
    .log 6 "Adding ${IP} as ${__ROLES[${IP}]}"
    case ${__ROLES[${IP}]} in
      "arbiter")
        .log 7 $(echo "rs.addArb(\"${IP}:${__PORT}\")" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet)
        ;;
      "hidden")
        .log 6 "Hidden instance will be configured next maintinance window."
        __RECONFIG=true
        ;;
      *)
        .log 7 $(echo "rs.add(\"${IP}:${__PORT}\")" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet)
        ;;
    esac
  done

  # build removal list
  STALE_IPS=()
  for IP in ${CONFIGURED_IPS}; do
    if ! .in_array ${IP} ${__CURRENT_IPS}; then
      STALE_IPS+=(${IP})
    fi
  done
  if [ ! -z "${STALE_IPS[@]}" ]; then .log 5 "Stale ips: ${STALE_IPS[@]}"; fi

  for IP in ${STALE_IPS}; do
    .log 5 "Removing ${IP} ( ${__ROLES[${IP}]} )"
    .log 7 $(echo "rs.remove(\"${IP}:${__PORT}\")" | $mongo ${PRIMARY}:${__PORT} ${__AUTHENTICATION[@]} --quiet)
  done
}

#
# MAIN
#
NEXT=$($cronexpr ${__MAINTENANCE})
.log 7 "Next maintenance window: ${NEXT}"

while true ; do
  DO_MAINTENANCE=false
  TODO=""

  if [ ${NEXT} -lt $(date +%s) ]; then
    .log 5 "Maintenance window (${__MAINTENANCE})"
    DO_MAINTENANCE=true
    NEXT=$($cronexpr ${__MAINTENANCE})
    .log 6 "Next maintenance window: ${NEXT}"

    if [ ! -z "${__TODO}" ]; then
      TODO=${__RECONFIG}
      __RECONFIG=""
    fi
  fi
  __CURRENT_IPS=$($dig +short ${SERVICE})

  if [ -z "${__CURRENT_IPS}" ]; then
    .log 2 "Nothing returned from: $dig +short ${SERVICE}"
    sleep ${__INTERVAL}
    continue
  fi

  .log 7 "Current ips: ${__CURRENT_IPS[@]}"
  ALLMETA=$(curl -s -H 'Accept: application/json' ${META_URL})
  PRIMARY=""

  for IP in ${__CURRENT_IPS} ; do
    __ROLES[${IP}]=$(echo ${ALLMETA} | $jq -r ".containers[] as \$c | .hosts[] | select(.uuid == (\$c | select(.ips[] == \"${IP}\") | .host_uuid) ) | .labels.${HOST_LABEL}")
    __ROLES[${IP}]=${__ROLES[${IP}],,}
    .log 7 "${IP}: ${__ROLES[${IP}]}"
    STATUS=$(echo "rs.status().myState" | $mongo ${IP}:${__PORT} ${__AUTHENTICATION[@]} --quiet)
    if [ $? -ne 0 ]; then
      CODE=$?
      .log 4 "${IP}: mongo client failed with ${CODE}." ${STATUS}
      STATUS=""
    else
      .log 7 "${IP}: myState ${STATUS}"
    fi

    if [ "${__ROLES[${IP}]}" == "null" ]; then
      .log 3 "${IP}: has no host label. Will be ignored."
      continue
    fi

    if [ -z "${TODO}" ] || [ "${TODO}" == "unknown" ]; then
      if [ -z "${TODO}" ] && [ "${STATUS}" != "" ]; then
        # At least one node in the cluster is not in 'startup' state
        TODO="unknown"
      fi
      case ${STATUS} in
        1) # PRIMARY
          PRIMARY=${IP}

          if [ "${__ROLES[${IP}]}" != "primary" ]; then
            .log 5 "${IP}: should be PRIMARY is ${STATUS}"
            TODO="reconfig"
          elif [ "${TODO}" != "reconfig" ]; then
            TODO="configured"
          fi

          ;;
        2) # SECONDARY - HIDDEN
          if [ "${__ROLES[${IP}]}" != "secondary" ] && [ "${__ROLES[${IP}]}" != "hidden" ]; then
            .log 5 "${IP}: should be ${__ROLES[${IP}]^^} is ${STATUS}"
            TODO="reconfig"
          fi
          ;;
        7) # ARBITER
          if [ "${__ROLES[${IP}]}" != "arbiter" ]; then
            .log 5 "${IP}: should be ARBITER is ${STATUS}"
            TODO="reconfig"
          fi
          ;;
      esac
      if [ -z "${PRIMARY}" ] && [ "${__ROLES[${IP}]}" == "primary" ]; then
        PRIMARY=${IP}
      fi
    fi
  done

  if [ -z "${TODO}" ]; then
    TODO="unconfigured"
  fi
  .log 7 "TODO: ${TODO}; AS PRIMARY: ${PRIMARY}"

  if [ -z "${PRIMARY}" ]; then
    .log 1 "There is no instance for PRIMARY"
    sleep ${__INTERVAL}
    continue
  fi

  case ${TODO} in
    "unconfigured")
      .reconfig true "${PRIMARY}"
      ;;
    "reconfig")
      if [ ${DO_MAINTENANCE} ]; then
        .reconfig false "${PRIMARY}"
      fi
      ;;
    "configured")
        .peers_check "${PRIMARY}"
      ;;
    "unknown")
      .log 4 "Status of replica set is unknown"
      ;;
  esac

  sleep ${INTERVAL}
done
