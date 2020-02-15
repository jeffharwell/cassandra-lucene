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

## Define some functions
create_directory_set_permissions() {
    ## first make sure that the variable isn't empty
    #whoami
    #echo "Varible is: --${1}--"
    if [ ! -z ${1+x} ]; then
        ## The enviroment value may have actual quotes, must strip those off (subtle)
        DIR=$(echo $1 | sed 's/^\"//g' | sed 's/\"$//g')
        #echo "Directory is --${DIR}--"
        if [ ! -d ${DIR} ]; then
            ## If it doesn't exist create it
            #echo "Creating Directory ${DIR}"
            mkdir -p ${DIR}     
        fi
        ## regardless make sure cassandra owns it
        chown -R cassandra ${DIR}
    fi
}


## This says that every variable defined is automatically push to the environment and 
## accessible to child processes.
set -e

## For debugging - if you want to understand the script flow.
## this would print twice, once as root, and then again as the cassandra
## user once gosu is used to re-run this script.
#echo "Script Run:"
#echo "I am: "
#whoami
#echo "I've been called with arguments: "
#echo "$@"
#echo "---"

##
## In the Dockerfile the CMD section is as follows:
##             "Cmd": [
##                "cassandra",
##                "-f"
##            ],
##
## So this script will be called as ./docker-entrypoint.sh cassandra -f

# first arg is `-f` or `--some-option`
# Basically the first argument needs to be the executable that we will eventually execute way at the
# end of the script. This section allows you to call the script and not specify cassandra as the 
# executable and it will go ahead and insert it. This isn't necessary in the specific case of this dockerfile
# because CMD is set up to always pass 'cassandra' as the first argument.
#
# In terms of syntax:
# ${1:0:1} the first 1 is the variable, the :0:1 takes the first character of the varible
if [ "${1:0:1}" = '-' ]; then
    ## see https://unix.stackexchange.com/questions/308260/what-does-set-do-in-this-dockerfile-entrypoint
    ## this puts the string "cassandra" in $1 and pushes eveything else forward
	set -- cassandra -f "$@"
fi

# If our first argument is cassandra (it it will be, see above) then re-run this script as the Cassandra user
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
    ## Before we drop privileges create the directories with proper permissions
	create_directory_set_permissions ${CASSANDRA_DATA_FILE_DIRECTORIES}
	create_directory_set_permissions ${CASSANDRA_HINTS_DIRECTORY}
	create_directory_set_permissions ${CASSANDRA_COMMITLOG_DIRECTORY}

	chown -R cassandra /var/lib/cassandra /var/log/cassandra "$CASSANDRA_CONFIG"
    ## BASH_SOURCE is built in, it is the relative name of the current bash script
    ## gosu just runs the whole thing as a specific user (it is an installed binary)
    ##
    ## Interestingly executing gosu here essentially ends the current execution, none of the
    ## other commands in this script will ever get executed as root. This run of the script ends
    ## at this point. When the process called by gosu finishes we do not return and finish
    ## executing this script as root.
	exec gosu cassandra "$BASH_SOURCE" "$@"
fi

## For debugging - if you want to understand the flow
## It shows that you never get to this point as root, only as the cassandra user
#
#echo "I am"
#whoami
#echo "and I've proceeded past the gosu command"

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
    ## This was my best first try
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
        ## ^^ means make the value uppercase
        ## https://stackoverflow.com/questions/11392189/how-to-convert-a-string-from-uppercase-to-lowercase-in-bash
		var="CASSANDRA_${yaml^^}"
        ## Indirect substitution, $val gets the value in the variable CASSANDRA_${yaml^^}
        ## https://unix.stackexchange.com/questions/41292/variable-substitution-with-an-exclamation-mark-in-bash
		val="${!var}"
        if [ "$val" ]; then
            sed -ri 's$^(# )?('"$yaml"':)(.*)$'"$yaml"': '"${val}"'$' "$CASSANDRA_CONFIG/cassandra.yaml"
        fi
    done

    ## These configuration parameters should all exist in cassandra.yaml but will be commented out
    ## if we have an environmental variable then we uncomment the line and set the value of the 
    ## parameter to the value specifed in the environmental variable
	for yaml in \
        broadcast_address \
        broadcast_rpc_address \
        cluster_name \
        endpoint_snitch \
        listen_address \
        num_tokens \
        rpc_address \
        start_rpc \
        allocate_tokens_for_keyspace \
	; do
		var="CASSANDRA_${yaml^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
		fi
	done

    ## These are configuration paramaters that defaut to true but should be false in production.
    ## They may or may not exist in cassandra.yaml and may or may not be commented out (yuck).
    ##
    ## We want to comment them out in the .yaml file if they exist and then either set 
    ## them to false or set them to the value specified the environmental variable
    ##
    ## See: https://github.com/jeffharwell/cassandra-lucene/issues/1
    ##to_disable=(materialized_views transient_replication)
    to_disable=(materialized_views)
    for yaml in ${to_disable[@]}; do
        var="CASSANDRA_${yaml^^}"
        val="${!var}"
        ## First comment out the line in if it does exist in cassandra.yaml
        parameter_name="enable_${yaml}"
        sed -ri 's/^'"${parameter_name}"'/# '"${parameter_name}"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
        ## new write in the new value if we have a varible for it, otherwise disable the feature
        if [ "$val" ]; then
            ## We have an environmental variable specifying the value of this parameter, use that
            echo "${parameter_name}: ${val}" >> "$CASSANDRA_CONFIG/cassandra.yaml"
        else
            ## There is no environmental variable specifying a value, disable the parameter
            echo "${parameter_name}: false" >> "$CASSANDRA_CONFIG/cassandra.yaml"
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

## Because of the gosu earlier in the script we will never hit this exec as root and actually call cassandra
## this is run as the cassandra user, and calls cassandra.
exec "$@"
