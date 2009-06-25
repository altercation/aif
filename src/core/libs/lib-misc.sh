#!/bin/bash


# runs a process and makes sure the output is shown to the user. sets the exit state of the executed program ($<identifier>_exitcode) so the caller can show a concluding message.
# when in dia mode, we will run the program and a dialog instance in the background (cause that's just how it works with dia)
# when in cli mode, the program will just run in the foreground. technically it can be run backgrounded but then we need tail -f (cli_follow_progress), and we miss the beginning of the output if it goes too fast, not to mention because of the sleep in run_background
# $1 identifier
# $2 command (will be eval'ed)
# $3 logfile
# $4 title to show while process is running
run_controlled ()
{
	[ -z "$1" ] && die_error "run_controlled: please specify an identifier to keep track of the command!"
	[ -z "$2" ] && die_error "run_controlled needs a command to execute!"
	[ -z "$3" ] && die_error "run_controlled needs a logfile to redirect output to!"
	[ -z "$4" ] && die_error "run_controlled needs a title to show while your process is running!"
	
	if [ "$var_UI_TYPE" = dia ]
	then
		run_background $1 "$2" $3
		follow_progress " $4 " $3 $BACKGROUND_PID # dia mode ignores the pid. cli uses it to know how long it must do tail -f
		wait_for $1 $FOLLOW_PID
	else
		notify "$4"
		var_exit=${1}_exitcode
		eval "$2" >>$3 2>&1
		read $var_exit <<< $?
	fi
}


# run a process in the background, and log it's stdout and stderr to a specific logfile
# returncode is stored in $<identifier>_exitcode
# pid of the backgrounded wrapper process is stored in BACKGROUND_PID (this is _not_ the pid of $2)
# $1 identifier -> WARNING: do never ever use -'s or other fancy characters here. only numbers, letters and _ please. (because $<identifier>_exitcode must be a valid bash variable!)
# $2 command (will be eval'ed)
# $3 logfile
run_background ()
{
	[ -z "$1" ] && die_error "run_background: please specify an identifier to keep track of the command!"
	[ -z "$2" ] && die_error "run_background needs a command to execute!"
	[ -z "$3" ] && die_error "run_background needs a logfile to redirect output to!"

	debug 'MISC' "run_background called. identifier: $1, command: $2, logfile: $3"
	( \
		touch $RUNTIME_DIR/aif-$1-running
		debug 'MISC' "run_background starting $1: $2 >>$3 2>&1"
		[ -f $3 ] && echo -e "\n\n\n" >>$3
		echo "STARTING $1 . Executing $2 >>$3 2>&1\n" >> $3;
		var_exit=${1}_exitcode
		eval "$2" >>$3 2>&1
		read $var_exit <<< $?
		debug 'MISC' "run_background done with $1: exitcode (\$$1_exitcode): ${!var_exit} .Logfile $3"
		echo >> $3   
		rm -f $RUNTIME_DIR/aif-$1-running
	) &
	BACKGROUND_PID=$!

	sleep 2
}


# wait until a process is done
# $1 identifier. WARNING! see above
# $2 pid of a process to kill when done (optional). useful for dialog --no-kill --tailboxbg's pid.
wait_for ()
{
	[ -z "$1" ] && die_error "wait_for needs an identifier to known on which command to wait!"

	while [ -f $RUNTIME_DIR/aif-$1-running ]
	do
		sleep 1
	done

	[ -n "$2" ] && kill $2
}


# $1 needle
# $2 set (array) haystack
check_is_in ()
{
	[ -z "$1" ] && die_error "check_is_in needs a non-empty needle as \$1 and a haystack as \$2!(got: check_is_in '$1' '$2'" # haystack can be empty though
	NEEDLE=$1
	HAYSTACK=$2

	local pattern="$NEEDLE" element
	shift
	for element
	do
		[[ $element = $pattern ]] && return 0
	done
	return 1
}


# cleans up file in the runtime directory who can be deleted, make dir first if needed
cleanup_runtime ()
{
	mkdir -p $RUNTIME_DIR || die_error "Cannot create $RUNTIME_DIR"
	rm -rf $RUNTIME_DIR/aif-dia* &>/dev/null
}


# $1 UTC or localtime (hardwareclock)
# $2 direction (systohc or hctosys)
# $3 selected TIMEZONE (optional)
dohwclock() {
	# TODO: we probably only need to do this once and then actually use adjtime on next invocations
	infofy "Resetting hardware clock adjustment file"
	[ ! -d /var/lib/hwclock ] && mkdir -p /var/lib/hwclock
	if [ ! -f /var/lib/hwclock/adjtime ]; then
		echo "0.0 0 0.0" > /var/lib/hwclock/adjtime
	fi

	infofy "Syncing clocks ($2), hc being $1 ..."
	if [ "$1" = "UTC" ]; then
		hwclock --$2 --utc
	else
		if [ ! "$3"x == "x" ]; then
			local ret=$(TZ=$3 hwclock --$2 --localtime) # we need the subshell so that TZ does not set in this shell
		else
			hwclock --$2 --localtime
		fi
	fi
}

target_configure_initial_keymap_font ()
{
	[ -n "$var_KEYMAP"      ] && sed -i "s/^KEYMAP=.*/KEYMAP=\"$var_KEYMAP\"/"                ${var_TARGET_DIR}/etc/rc.conf
	[ -n "$var_CONSOLEFONT" ] && sed -i "s/^CONSOLEFONT=.*/CONSOLEFONT=\"$var_CONSOLEFONT\"/" ${var_TARGET_DIR}/etc/rc.conf
}
