#!/bin/bash

curl=/usr/bin/curl
jq=/usr/bin/jq
dig=/usr/bin/dig
mongo=/usr/bin/mongo

function join { local IFS="$1"; shift; echo "$*"; }

function in_array {
  key=$1
  shift
  values=$@
  for entry in $values ; do
    if [ "$key" == "$entry" ]; then
      return 0
    fi
  done
  return 1
}

previous_version=0
while true ; do
  #Something has changed
  current_ips=$($dig +short ${SERVICE})
  # Determine if any replica set exists by iterating over the pods and checking rs.status()
  state="unconfigured"
  primary_ip=""
  for ip in ${current_ips} ; do
    # Does a replica set config exist?
    echo $ip
    instance_status=$(echo "rs.status().myState" | $mongo --host ${ip} --quiet)
    echo $instance_status
    if [[ "${instance_status}" != "" ]] ; then
      # At least one node in the cluster is not in 'startup' state
      state="unknown"
    fi
    if [[ "${instance_status}" == "1" ]] ; then
      # found primary
      state="configured"
      primary_ip=${ip}
      break
    fi
    primary_ip=${ip}
  done

  echo $state

  case ${state} in
    "unconfigured")
      # Cluster completely unconfigured.  Generate config json and load on first node
      id=0
      host_array=()
      for ip in ${current_ips} ; do
        host_array+=("{ \"_id\": ${id}, \"host\":\"${ip}\" }")
        id=$(($id + 1))
      done
      host_json=$(join , "${host_array[@]}")
      config_json="{ \"_id\": \"${MONGO_REPLSET}\", \"members\": [ ${host_json} ]}"
      clean_json=$(echo ${config_json} | $jq -c .)
      echo ${clean_json}

      case $(echo "rs.status()" | $mongo --host ${primary_ip} --quiet | $jq -r '.code') in
        94)
          # { "info" : "run rs.initiate(...) if not yet done for the set", "ok" : 0, "errmsg" : "no replset config has been received", "code" : 94 } 
          echo "if ( rs.initiate().ok ) rs.reconfig(${clean_json},{force: true})" | $mongo ${primary_ip} --quiet
          ;;
        *)
          echo "rs.reconfig(${clean_json},{force: true})" | $mongo ${primary_ip} --quiet
          ;;
      esac
      ;;
    "configured")
      # Cluster configured, sync host list via primary
      configured_ips=$(echo "rs.conf()" | $mongo ${primary_ip} --quiet | $jq .members[].host | sed 's/\"\([^:]*\):\([^:]*\)\"/\1/g')
      echo ${configured_ips}
      # build additions list
      new_ips=()
      for ip in ${current_ips}; do
        if ! in_array ${ip} ${configured_ips}; then
          new_ips+=(${ip})
        fi
      done
      echo $new_ips
      for ip in $new_ips; do
             echo "rs.add(\"$ip\")" | $mongo ${primary_ip} --quiet
      done

      # build removal list
      stale_ips=()
      for ip in ${configured_ips}; do
        if ! in_array ${ip} ${current_ips}; then
          stale_ips+=(${ip})
        fi
      done
      echo $stale_ips
      for ip in $stale_ips; do
        echo "rs.remove(\"$ip:27017\")" | $mongo ${primary_ip} --quiet
      done
      ;;
         *)
      ;;
  esac

  sleep 30
done
