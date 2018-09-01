#!/bin/bash
#
# Copyright 2017 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# first arg is `-f` or `--some-option`
if [ "${1:0:1}" = '-' ]; then
	set -- cassandra -f "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
	chown -R cassandra /var/lib/cassandra /var/log/cassandra "$CASSANDRA_CONFIG"
	exec gosu cassandra "$BASH_SOURCE" "$@"
    ## Make sure cassandra has rights on the cassandra-data directory, this is where you would
    ## mount persistant storage in a cluster environment.
    chown -R cassandra /cassandra_data
fi

create_directory_set_permissions() {
    ## first make sure that the variable isn't empty
    whoami
    echo "Varible is: --${1}--"
    if [ ! -z ${1+x} ]; then
        ## The enviroment value may have actual quotes, must strip those off (subtle)
        DIR=$(echo $1 | sed 's/^\"//g' | sed 's/\"$//g')
        echo "Directory is --${DIR}--"
        if [ ! -d ${DIR} ]; then
            ## If it doesn't exist create it
            echo "Creating Directory ${DIR}"
            mkdir -p ${DIR}     
        fi
        ## regardless make sure cassandra owns it
        chown -R cassandra ${DIR}
    fi
}

## Create and give proper permissions to our data, hints, and commitlog directories
## if they are defined (the function above takes care of that check
create_directory_set_permissions ${CASSANDRA_DATA_FILE_DIRECTORIES}
create_directory_set_permissions ${CASSANDRA_HINTS_DIRECTORY}
create_directory_set_permissions ${CASSANDRA_COMMITLOG_DIRECTORY}

## Write environmental variables into the $CASSANDRA_CONFIG/cassandra.yaml file
if [ "$1" = 'cassandra' ]; then
	: ${CASSANDRA_RPC_ADDRESS='0.0.0.0'}

	: ${CASSANDRA_LISTEN_ADDRESS='auto'}
	if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
		CASSANDRA_LISTEN_ADDRESS="$(hostname --ip-address)"
	fi

	: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}

	if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
		CASSANDRA_BROADCAST_ADDRESS="$(hostname --ip-address)"
	fi
	: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

	if [ -n "${CASSANDRA_NAME:+1}" ]; then
		: ${CASSANDRA_SEEDS:="cassandra"}
	fi
	: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}
	
	sed -ri 's/(- seeds:).*/\1 "'"$CASSANDRA_SEEDS"'"/' "$CASSANDRA_CONFIG/cassandra.yaml"

    if [ -n "${CASSANDRA_AUTO_BOOTSTRAP:+1}" ]; then
        ## auto bootstrap defaults to true and is not exposed in the cassandra.yaml
        echo "auto_bootstrap: ${CASSANDRA_AUTO_BOOTSTRAP}" >> "${CASSANDRA_CONFIG}/cassandra.yaml"
    fi

    ## this is pretty bad
    ## The data_file_directories is a multi-line configuration, which is a bit tricky to substitute
    ## This was much best first try
	if [ -n "${CASSANDRA_DATA_FILE_DIRECTORIES:+1}" ]; then
		## this is multi line yaml directive ... uugh ... this command get the line right after the data_file_directories line
		next_line="$(awk 'f{print;f=0} /(^# )?(data_file_directories)/{f=1}' ${CASSANDRA_CONFIG}/cassandra.yaml)"

		## comment out the existing data_file_directories line
		sed -ri 's/(^# )?(data_file_directories:).*/# \2/' ${CASSANDRA_CONFIG}/cassandra.yaml
		## comment out the line after the existing directories line
		sed -ri 's_('"$next_line"')_# \1_' ${CASSANDRA_CONFIG}/cassandra.yaml

		## now insert our desired configuration after the line we just commented out
		sed -i '\_'"$next_line"'_a \
data_file_directories: \
    - '"${CASSANDRA_DATA_FILE_DIRECTORIES}"'' ${CASSANDRA_CONFIG}/cassandra.yaml
	fi


    for yaml in \
        hints_directory \
        commitlog_directory \
    ; do
		var="CASSANDRA_${yaml^^}"
		val="${!var}"
        if [ "$val" ]; then
            sed -ri 's$^(# )?('"$yaml"':)(.*)$'"$yaml"': '"${val}"'$' "$CASSANDRA_CONFIG/cassandra.yaml"
        fi
    done

	for yaml in \
		broadcast_address \
		broadcast_rpc_address \
		cluster_name \
		endpoint_snitch \
		listen_address \
		num_tokens \
		rpc_address \
		start_rpc \
	; do
		var="CASSANDRA_${yaml^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
		fi
	done

	for rackdc in dc rack; do
		var="CASSANDRA_${rackdc^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^('"$rackdc"'=).*/\1 '"$val"'/' "$CASSANDRA_CONFIG/cassandra-rackdc.properties"
		fi
	done
fi

exec "$@"
