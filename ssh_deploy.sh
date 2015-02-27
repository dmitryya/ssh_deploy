#!/bin/sh

SCP_BIN=`which scp`
SSH_BIN=`which ssh`
SSHPASS_BIN="`dirname $0`/sshpass"
TAR_BIN=`which tar`

hosts_file=""
dest_dir=""
verbose=0

show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-f FILE] [-d DEST DIR] [DIR or FILE]...[DIR or FILE]
Copy DIRs or FILEs to DEST DIR on remote hosts. Hosts are in FILE. 
FILE format: 
        username:password@host:port
        ...
        username:password@host:port
Options:
    -h          display this help and exit.
    -f FILE     FILE with HOSTs.
    -d DEST DIR DEST DIR on the remote host 
    -v          verbose mode.
EOF
}

log() {
    if [ $verbose -gt 0 ]; then 
        echo "$1"
    fi
}

check_env() {
	if [ -z "$SCP_BIN" ]
	then
	    echo "Can't find scp binary" >&2 
	    exit 1
	fi

	if [ -z "$SSH_BIN" ]
	then
	    echo "Can't find ssh binary" >&2 
	    exit 1
	fi

	if [ -z "$TAR_BIN" ]
	then
	    echo "Can't find tar binary" >&2 
	    exit 1
	fi


	if [ ! -f "$SSHPASS_BIN" ]
	then
	    echo "Can't find sshpass binary in local dir" >&2 
	    exit 1
	fi
}

while getopts "hvf:d:" opt; do
    case "$opt" in
        h)
            show_help
            exit 0
            ;;
        f)
            hosts_file=$OPTARG
            ;;
        d)
            dest_dir=$OPTARG
            ;;
        v)
            verbose=1
            ;;
        ?)
            show_help >&2 
            exit 1
    esac
done

shift "$((OPTIND-1))" # Shift off the options and optional --.

if [ -z "$hosts_file" ] || [ -z "$dest_dir" ]
then 
    echo "Missing option -f or -d" >&2
    show_help >&2
    exit 1
fi

check_env 

TMP_FILE="`basename $0`-$$-`date +'%s'`".tar

for file in $@
do
    log "Add $file to archive $TMP_FILE."
    $TAR_BIN --append --file="/tmp/$TMP_FILE" -C `dirname $file` `basename $file`
done

for line in `cat $hosts_file`; 
do
    TMP=`echo $line | cut -f1 -d\@`
    HOST=`echo $line | rev | cut -f1 -d\@ | rev`
    TMP=`echo $line | rev | cut -f2- -d\@ | rev`

    if [ "$TMP" != "$line" ];
    then 
            USR=`echo $TMP | cut -f1 -d\:`
            if [ $USR != $TMP ];
            then
                PASSWD=`echo $TMP | cut -f2- -d\:`
            fi
        
    fi

    if [ `echo $HOST | cut -f1 -d\:` != $HOST ];
    then
        PORT=`echo $HOST | cut -f2 -d\:`
        HOST=`echo $HOST | cut -f1 -d\:`
    fi

    if [ "$PASSWD" ]
    then 
        SSHPASS_CMD="$SSHPASS_BIN -p $PASSWD"
    fi
    
    if [ $USR ];
    then
        HOST=$USR@$HOST
    fi

    if [ $PORT ];
    then
        SCP_ARGS="-P $PORT"
        SSH_ARGS="-p $PORT"
    fi 

    log "Send to '$line' - USER '$USR'; PASSWORD '$PASSWD'; HOST '$HOST'; PORT '$PORT'" 
    $SSHPASS_CMD $SCP_BIN $SCP_ARGS "/tmp/$TMP_FILE" $HOST:/$dest_dir/
    log "Extract from archive on the remote host"
    $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "tar xf /$dest_dir/$TMP_FILE -C /$dest_dir/ && rm -f /$dest_dir/$TMP_FILE"
done

rm -f "/tmp/$TMP_FILE"

exit 0
