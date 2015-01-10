#!/bin/sh

CURL=/usr/bin/curl
JQ=/usr/bin/jq
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
        jsondata=$(curl -q -L "http://${KUBERNETES_HOST_PORT}/api/v1beta1/pods?labels=${SELECTOR}" 2>/dev/null)
        current_version=$(echo ${jsondata} | jq '[.items[]|.resourceVersion]|max')
        if [[ "${current_version}" -gt "${previous_version}" ]] ; then
                #Something has changed
                current_ips=$(echo ${jsondata} | jq -a .items[].currentState.podIP | sed 's/\"\([^\"]*\)\"/\1/g' | grep -v null)
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
                state="unconfigured"

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
                                config_json="{ \"_id\": \"${MONGODB_REPLSET}\", \"members\": [ ${host_json} ]}"
                                clean_json=$(echo ${config_json} | jq -c .)
                                echo $clean_json
                                echo "rs.reconfig($clean_json,{force: true})" | /usr/bin/mongo ${primary_ip} --quiet
                		previous_version=$current_version
                                ;;
                        "configured")
                                # Cluster configured, sync host list via primary
				configured_ips=$(echo "rs.conf()" | /usr/bin/mongo ${primary_ip} --quiet | jq .members[].host | sed 's/\"\([^:]*\):\([^:]*\)\"/\1/g')
				echo ${configured_ips}
                                # build additions list
                                new_ips=()
                                for ip in ${current_ips}; do
                                        if ! in_array ${ip} ${configured_ips}; then
                                                new_ips+=(${ip})
                                        fi
                                done
                                echo $new_ips
                                # build removal list
                                stale_ips=()
                                for ip in ${configured_ips}; do
                                        if ! in_array ${ip} ${current_ips}; then
                                                stale_ips+=(${ip})
                                        fi
                                done
                                echo $stale_ips
                		previous_version=$current_version
                                ;;
                        *)
                                ;;
                esac

        fi
        sleep 30
done

