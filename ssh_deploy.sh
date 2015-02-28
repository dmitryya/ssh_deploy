#!/bin/sh

SSH_DEPLOY=$0
SCP_BIN=`which scp`
SSH_BIN=`which ssh`
SSHPASS_BIN="`dirname $0`/sshpass"
TAR_BIN=`which tar`

SSH_ARGS='-oStrictHostKeyChecking=no'

VERBOSE=false

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
    -v          VERBOSE mode.
EOF
}

log() {
    if [ $VERBOSE = true ]; then
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

get_credentials() {

    TMP=`echo $1 | cut -f1 -d\@`
    HOST=`echo $1 | rev | cut -f1 -d\@ | rev`
    TMP=`echo $1 | rev | cut -f2- -d\@ | rev`

    if [ "$TMP" != "$1" ];
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
        SSH_ARGS="$SSH_ARGS -p $PORT"
    fi
}

while getopts "hvf:d:p:r:" opt; do
    case "$opt" in
        h)
            show_help
            exit 0
            ;;
        f)
            HOST_FILE=$OPTARG
            log "File with hosts - $HOST_FILE"
            ;;
        p)
            HOP_NEXT=$OPTARG
            eval HOP=\$$OPTIND
            while [ $# -ge $OPTIND ] && [ `expr match $HOP '^-.*'` -eq 0 ];
            do
                HOP_LIST="$HOP_LIST $HOP"
                OPTIND=$(($OPTIND + 1))
                eval HOP=\$$OPTIND
            done
            log "HOP LIST - $NEXT_HOP $HOP_LIST"
            ;;
        r)
            TAR_FILE=$OPTARG
            ;;
        d)
            DEST_DIR=$OPTARG
            log "Destination dir - $DEST_DIR"
            ;;
        v)
            VERBOSE=true
            ;;
        ?)
            show_help >&2 
            exit 1
    esac
done

shift "$((OPTIND-1))" # Shift off the options and optional --.

if [ "$HOST_FILE" ] && [ "$HOP_NEXT" ]
then
    echo "Contradictory options -f and -p" >&2
    show_help >&2
    exit 1
fi

if [ -z $HOP_NEXT ] && ([ -z "$HOST_FILE" ] || [ -z "$DEST_DIR" ])
then 
    echo "Missing option -f or -d" >&2
    show_help >&2
    exit 1
fi

check_env 

for file in $@
do
    TMP_FILE="`basename $0`-$$-`date +'%s'`".tar
    TMP_DIR='/tmp/'

    log "Add $file to archive $TMP_FILE."
    $TAR_BIN --append --file="/$TMP_DIR/$TMP_FILE" -C `dirname $file` `basename $file`
done

if [ "$HOST_FILE" ] && [ "$TMP_FILE" ]
then
    for line in `cat $HOST_FILE`
    do
        get_credentials $line

        log "Send to '$line' - USER '$USR'; PASSWORD '$PASSWD'; HOST '$HOST'; PORT '$PORT'"
        $SSHPASS_CMD $SCP_BIN $SCP_ARGS "/$TMP_DIR/$TMP_FILE" $HOST:/$DEST_DIR/
        log "Extract from archive on the remote host"
        $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "tar xf /$DEST_DIR/$TMP_FILE -C /$DEST_DIR/ && rm -f /$DEST_DIR/$TMP_FILE"
    done

    rm -f "/$TMP_DIR/$TMP_FILE"

fi

if [ "$HOP_NEXT" ] && ([ "$TMP_FILE" ] || [ "$TAR_FILE" ])
then
        get_credentials $HOP_NEXT
        if [ "$TAR_FILE" ]
        then
            TMP_DIR=`dirname $TAR_FILE`
            TMP_FILE=`basename $TAR_FILE`
            DO_NOT_CLEAN=true
        fi

        log "Send to '$HOP_NEXT' - USER '$USR'; PASSWORD '$PASSWD'; HOST '$HOST'; PORT '$PORT'"
        $SSHPASS_CMD $SCP_BIN $SCP_ARGS "/$TMP_DIR/$TMP_FILE" $HOST:/$DEST_DIR/
        $SSHPASS_CMD $SCP_BIN $SCP_ARGS $SSH_DEPLOY $HOST:/$DEST_DIR/
        $SSHPASS_CMD $SCP_BIN $SCP_ARGS $SSHPASS_BIN $HOST:/$DEST_DIR/
        if [ -z "$HOP_LIST" ]
        then
            log "Extract from archive on the remote host"
            $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "tar xf /$DEST_DIR/$TMP_FILE -C /$DEST_DIR/ && rm -f /$DEST_DIR/$TMP_FILE"
        else
            log "Run next hop"
            $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "/$DEST_DIR/`basename $SSH_DEPLOY` -v -p $HOP_LIST -d $DEST_DIR -r /$DEST_DIR/$TMP_FILE && \
                            (rm -f /$DEST_DIR/`basename $SSH_DEPLOY`; rm -f /$DEST_DIR/`basename $SSHPASS_BIN`; rm -f /$DEST_DIR/$TMP_FILE)"

        fi
        if [ -z "$TAR_FILE" ]
        then
            rm -f $TMP_FILE
        fi
fi

exit 0
