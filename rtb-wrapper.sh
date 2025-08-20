#!/usr/bin/env sh
# profile based rsync-time-backup
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

# Print CLI usage help
fn_display_usage () {
	echo "Usage: rtb-wrapper.sh <action> <profile>"
	echo ""
	echo "action: backup, restore"
	echo "profile: name of the profile file"
	echo ""
	echo "For more detailed help, please see the README file:"
	echo ""
	echo "https://github.com/lucaf/rtb-wrapper/blob/read-rsync-bin-from-env/README.md"
}

# create backup cli command
fn_create_backup_cmd () {
    cmd="${RSYNC_TMBACKUP_BIN} ${RSYNC_TMBACKUP_ARGS} '${BACKUP_SOURCE}' '${BACKUP_TARGET}'"

    exclude_file_check=${EXCLUDE_FILE:-}

    if [ ! -z "${exclude_file_check}" ]; then
        cmd="${cmd} '${EXCLUDE_FILE}'"
    fi

    echo "$cmd"
}

# create restore cli command
fn_create_restore_cmd () {
    if [ "$USE_SSH" == "false" ]; then
         cmd="${RSYNC_BIN} -aP"
         if [ "${WIPE_SOURCE_ON_RESTORE:-'false'}" = "true" ]; then
            cmd="${cmd} --delete"
         fi
    else
        ssh_cmd="${SSH_BIN} ${SSH_ARGS} ${SSH_RESTORE_ARGS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

        if [ "${WIPE_SOURCE_ON_RESTORE:-'false'}" = "true" ]; then
            cmd="${RSYNC_BIN} -e '${ssh_cmd} -aP --delete'"
        else 
            cmd="${RSYNC_BIN} -e '${ssh_cmd} -aP'"
        fi
    fi
    if [ -z "${RESTORE_TARGET}" ]; then
        echo " [!] The restore target directory is not defined: ${RESTORE_TARGET}" > /dev/stderr
        exit 1
    fi
    if [ ! -d "${RESTORE_TARGET}" ]; then
        mkdir -p "${RESTORE_TARGET}"
    fi
    
    cmd="${cmd} -- '${BACKUP_TARGET}/latest/' '${RESTORE_TARGET}/'"
    echo "$cmd"
}

fn_abort_if_crlf () {
    if ! awk '/\r$/ { exit(1) }' "$1"; then
        echo " [!] The profile has at least one Windows-style line ending"
        echo "     ERROR: failed to read the profile file: ${profile_file}" > /dev/stderr
        exit 1
    fi
}

# show help when invoked without parameters
if [ $# -eq 0 ]; then
    fn_display_usage
    exit 0
fi

action=${1?"param 1: action: backup, restore"}
profile=${2?"param 2: name of the profile"}

# load config
config_dir=${RTB_CONFIG_DIR:-"${HOME}/.rsync_tmbackup"}

# load profile
profile_dir="${config_dir}/conf.d"
profile_file="${profile_dir}/${profile}.inc"
exclude_file_convention="${profile_dir}/${profile}.excludes.lst"

if [ -r "$profile_file" ]; then
    # preset exclude file path before reading the profile
    if [ -r "$exclude_file_convention" ]; then
        EXCLUDE_FILE="$exclude_file_convention"
    fi

    # sanity check, crlf can break variable substitution
    fn_abort_if_crlf "$profile_file"

    # shellcheck disable=SC1090,SC1091
    . "$profile_file"

    # Complete environment variables
    if [ -z "$RSYNC_TMBACKUP_BIN" ]; then
		RSYNC_TMBACKUP_BIN=$(which rsync_tmbackup.sh)
	fi
    if [ ! -x "$RSYNC_TMBACKUP_BIN" ]; then
		echo "[!] Can't find an executable rsync_tmbackup.sh: check if it's installed, then update PATH env var or set RSYNC_TMBACKUP_BIN env var." > /dev/stderr
		exit 1
	fi
    if [ -z "$RSYNC_BIN" ]; then
		RSYNC_TMBACKUP_BIN=$(which rsync)
	fi
    if [ ! -x "$RSYNC_BIN" ]; then
		echo "[!] Can't find an executable rsync: check if it's installed, then update PATH env var or set RSYNC_BIN env var." > /dev/stderr
		exit 1
	fi 
    if [ -z "$SSH_BIN" ] && [ -z "$SSH_ARGS" ] && [ -z "$SSH_RESTORE_ARGS" ]; then
        USE_SSH=false 
    else
        USE_SSH=true
    fi
    if [ -z "$SSH_BIN" ]; then
        SSH_BIN=$(which ssh)
    fi
    if [ ! -x "$SSH_BIN" ]; then
        echo "[!] Can't find an executable ssh: check if it's installed, then update PATH env var or set SSH_BIN env var." > /dev/stderr
        exit 1
    fi

    # exports user defined RSYNC_BIN
    export RSYNC_BIN
    export SSH_BIN
    export SSH_ARGS

    # create cli command
    if [ "$action" = "restore" ]; then
        cmd=$(fn_create_restore_cmd)
    else
        cmd=$(fn_create_backup_cmd)
    fi

    echo "# ${cmd}"
    eval "$cmd"
else
    echo "Failed to read the profile file: ${profile_file}" > /dev/stderr
    exit 1
fi
