#!/bin/sh

SSH_DEPLOY=$0
SCP_BIN=`which scp`
SSH_BIN=`which ssh`
SSHPASS_BIN="`dirname $0`/sshpass"
TAR_BIN=`which tar`
REALPATH=`which realpath`

SSH_ARGS='-oStrictHostKeyChecking=no'

VERBOSE=false


show_help() {
cat << EOF
Usage: ${0##*/} [-h] [ [-f FILE] [-n NUM] | [-p HOST .. HOST] ] [-d DEST DIR] [ -a [TAR FILE] | [DIR or FILE]...[DIR or FILE]]
Copy DIRs or FILEs to DEST DIR on remote hosts. Hosts are in FILE.
FILE format:
        username:password@host:port
        ...
        username:password@host:port
HOST format:
        <user>:<password>@<host name or ip>:<port>
Options:
    -h                  display this help and exit.
    -f FILE             FILE with HOSTs.
    -p HOST ... HOST    Hosts which will be used as hops to send FILEs
    -d DEST DIR         Destination DIR on the remote host
    -a TAR FILE         TAR archive for sending instead of DIRs or FILEs
    -n NUM              NUM of parallel clients
    -v                  VERBOSE mode.
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


get_config() {

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


get_abs_path() {
    ret="$1"
    if [ "$REALPATH" ]
    then
        ret=`$REALPATH $1`
    fi
    echo "$ret"
}


send_to_host() {
    # $1 - HOST
    # $2 - DEST dir
    # $3..n - FILEs

    get_config $1

    dest_dir=$2

    log "Send to '$1' - USER '$USR'; PASSWORD '$PASSWD'; HOST '$HOST'; PORT '$PORT'"

    shift 2
    $SSHPASS_CMD $SCP_BIN $SCP_ARGS $@ $HOST:/$dest_dir/
}


untar_on_host() {
    # $1 - REMOTE HOST
    # $2 - FILE
    # $3 - DEST dir

    get_config $1

    log "Extract $2 on the remote host $1"
    $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "tar xf $2 -C /$3/"
}


remove_on_host() {
    # $1 - REMOTE HOST
    # $2..n - FILEs

    get_config $1

    log "Remove $2 on the remote host $1"
    shift
    $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "rm -f $@"
}


send_to_hops() {
    # $1 - HOST
    # $2 - HOP_LIST
    # $3 - DEST
    # $4 - FILE
    get_config $1
    log "Send to next hop"
    $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "/$3/`basename $SSH_DEPLOY` -v -p $2 -d $3 -a $4"
}

send_via_host() {
    # $1 - HOST
    # $2 - HOST file
    # $3 - DEST
    # $4 - FILE
    get_config $1

    log "Send file $4 via $1 host. HOST file $2"
    TMP_SCRIPT="`basename $SSH_DEPLOY`-node_agent-`date +'%s'`.sh"
    $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "cat > /$3/$TMP_SCRIPT << EOF
#!/bin/sh
/$3/`basename $SSH_DEPLOY` -v -f /$3/$2 -d $3 -a $4 && (rm -f /$3/`basename $SSH_DEPLOY` /$3/sshpass /$3/$2 /$3/$TMP_SCRIPT $4)
EOF"
    send_to_host $1 "$3" $2 $SSH_DEPLOY $SSHPASS_BIN

    log "Start upload on remote host $1."
    $SSHPASS_CMD $SSH_BIN $SSH_ARGS $HOST "nohup /bin/sh /$3/$TMP_SCRIPT > /dev/null 2> /dev/null < /dev/null &"
}

split_file() {
    # $1 - FILE
    # $2 - Parallel num

    log "Split HOSTs file"
    num=`wc -l $1 | cut -f1 -d \ `
    log "Lines in file $1: $num"
    HOST_LOCAL="/tmp/`basename $SSH_DEPLOY`-local_host-`date +'%s'`"
    HOST_TMP_REMOUTE="/tmp/`basename $SSH_DEPLOY`-remote_tmp_host-`date +'%s'`"
    head -n $2 $1 > $HOST_LOCAL
    tail -n $(($num - $2)) $1 > $HOST_TMP_REMOUTE
    num=$(($num - $2))
    if [ $num -gt 0 ]
    then
        suffix="`basename $SSH_DEPLOY`-hosts_file-`date +'%s'`"
        split -l $(($num / $2 + 1)) --additional-suffix=-$suffix $HOST_TMP_REMOUTE
        rm -f $HOST_TMP_REMOUTE
        HOSTS_FILE_LIST=`find ./ -name x\*-$suffix -printf '%p '`
    fi
}

while getopts "hvf:d:p:a:n:" opt; do
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
        a)
            TAR_FILE=$OPTARG
            ;;
        n)
            PNUM=$OPTARG
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

if [ "$TAR_FILE" ]
then
    TAR_FILE=$(get_abs_path $TAR_FILE)
    TMP_DIR=`dirname $TAR_FILE`
    TMP_FILE=`basename $TAR_FILE`
    DO_NOT_CLEAN=true
else
    for file in $@
    do
        TMP_FILE="`basename $0`-$$-`date +'%s'`".tar
        TMP_DIR='/tmp/'

        log "Add $file to archive $TMP_FILE."
        $TAR_BIN --append --file="/$TMP_DIR/$TMP_FILE" -C `dirname "$file"` `basename "$file"`
    done
fi

if [ "$HOST_FILE" ] && [ "$TMP_FILE" ]
then
    HOSTS="$HOST_FILE"
    if [ "$PNUM" ]
    then
        split_file $HOST_FILE $PNUM
        HOSTS=$HOST_LOCAL
        if [ "$HOSTS_FILE_LIST" ]
        then
            set $HOSTS_FILE_LIST
        fi
    fi

    for host in `cat $HOSTS`
    do
        send_to_host $host $DEST_DIR "/$TMP_DIR/$TMP_FILE"
        untar_on_host $host "/$DEST_DIR/$TMP_FILE" "$DEST_DIR"
        if [ "$#" -gt 0 ]
        then
            send_via_host $host "$1" $DEST_DIR "/$DEST_DIR/$TMP_FILE"
            shift
        else
            remove_on_host $host "/$DEST_DIR/$TMP_FILE"
        fi
    done

    [ "$HOST_LOCAL" ] && (rm -f $HOST_LOCAL)
    [ "$HOSTS_FILE_LIST" ] && (rm -f $HOSTS_FILE_LIST)
fi

if [ "$HOP_NEXT" ] && ([ "$TMP_FILE" ] || [ "$TAR_FILE" ])
then
    if [ "$HOP_LIST" ]
    then
        EXTRA_FILES="$SSH_DEPLOY $SSHPASS_BIN"
    fi
    send_to_host $HOP_NEXT $DEST_DIR "/$TMP_DIR/$TMP_FILE" $EXTRA_FILES
   [ -z "$HOP_LIST" ] && (untar_on_host $HOP_NEXT "/$DEST_DIR/$TMP_FILE" "$DEST_DIR" ; \
        remove_on_host $HOP_NEXT "/$DEST_DIR/$TMP_FILE")

    [ "$HOP_LIST" ] && send_to_hops "$HOP_NEXT" "$HOP_LIST" "/$DEST_DIR" "/$TMP_DIR/$TMP_FILE"
    remove_on_host $HOP_NEXT /$DEST_DIR/`basename $SSH_DEPLOY` /$DEST_DIR/`basename $SSHPASS_BIN` /$DEST_DIR/$TMP_FILE
fi

if [ -z "$TAR_FILE" ]
then
    rm -f /$TMP_DIR/$TMP_FILE
fi

exit 0
