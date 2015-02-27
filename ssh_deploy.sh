#!/bin/sh

SCP_BIN=`which scp`
SSHPASS_BIN="`pwd`/sshpass"
TAR_BIN=`which tar`

hosts_file=""
dest_dir=""
verbose=0

TMP_FILE=`mktemp`

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

if [ -z "$hosts_file" ] || [ -z "$dest_dir" ]
then 
    echo "Missing option -f or -d" >&2
    show_help >&2
    exit 1
fi

if [ -z "$SCP_BIN" ]
then
    echo "Can't find scp binary" >&2 
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

if [ -z "$TMP_FILE" ]
then
    TMP_FILE="/tmp/$$-`date +'%s'`.tmp"
fi

TMP_FILE="$TMP_FILE.tar"
echo $TMP_FILE

shift "$((OPTIND-1))" # Shift off the options and optional --.

for file in $@
do
    log "Add $file to archive $TMP_FILE."
    $TAR_BIN --append --file=$TMP_FILE -C `dirname $file` `basename $file`
done

for line in `cat $hosts_file`; 
do
    USR=
    PASSWD=
    PORT=
    ARGS=

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

    log "Send to '$line' - USER '$USR'; PASSWORD '$PASSWD'; HOST '$HOST'; PORT '$PORT'" 

    CMD_PREFIX=
    if [ "$PASSWD" ]
    then 
        CMD_PREFIX="$SSHPASS_BIN -p $PASSWD"
    fi
    
    if [ $USR ];
    then
        HOST=$USR@$HOST
    fi
    if [ $PORT ];
    then
        ARGS="-P $PORT"
    fi 

    $CMD_PREFIX $SCP_BIN $TMP_FILE $HOST:/$dest_dir/
done

exit 0
