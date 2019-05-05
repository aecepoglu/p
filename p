#!/usr/bin/env sh

#set -e

LOG=${LOGFILE-$HOME/.config/p/log}
DATE_FORMAT="%Y-%m-%d %T %z"
POMODORO_LENGTH_IN_SECONDS=1500
POMODORO_BREAK_IN_SECONDS=300
PREFIX="🍅 "
INTERNAL_INTERRUPTION_MARKER="'"
EXTERNAL_INTERRUPTION_MARKER="-"
DATE=date

deleteLastLine() {
  if [ -s "$LOG" ]; then
    tmpfile=$(mktemp)
    head -n -2 $LOG > $tmpfile
    mv $tmpfile $LOG
  fi
}

convertTimeFormat() {
  TIME_STRING="$1"
  OUTPUT_FORMAT="$2"
  $DATE --version 2>&1 | grep "GNU coreutils" > /dev/null
  if [ "$?" -eq "0" ]; then
    $DATE -d "$TIME_STRING" "$OUTPUT_FORMAT"
  else
    $DATE -j -f "$DATE_FORMAT" "$TIME_STRING" "$OUTPUT_FORMAT"
  fi
}

myCheckLastPomodoro() {
  if [ -s "$LOG" ]; then
    RECENT=$(tail -1 ${LOG})
    TIME=$(echo $RECENT | cut -d ',' -f 1)
    INTERRUPTIONS=$(echo $RECENT | cut -d ',' -f 2)
    THING=$(echo $RECENT | cut -d ',' -f 3-)
    TIMESTAMP_RECENT=$(convertTimeFormat "$TIME" "+%s")
    TIMESTAMP_NOW=$($DATE "+%s")
    SECONDS_ELAPSED=$((TIMESTAMP_NOW - TIMESTAMP_RECENT))

    if [ $SECONDS_ELAPSED -ge $POMODORO_LENGTH_IN_SECONDS ]; then
      return 1
    else
      return 0
    fi
  else
    return 2
  fi
}

cancelRunningPomodoro() {
  if myCheckLastPomodoro; then
    deleteLastLine
    echo $1
  fi
}

interrupt() {
  type=$1
  myCheckLastPomodoro
  retval="$?"
  if [ "$retval" == "0" ]; then
    deleteLastLine
    echo $TIME,$INTERRUPTIONS$type,$THING >> "$LOG"
    echo "Interrupt recorded"
 elif [ "$retval" == "1" ]; then
    echo "No pomodoro to interrupt"
    exit 1
  fi
}

optionalDescription() {
  OPTIONAL_THING="$1"
  if [ ! -z "${OPTIONAL_THING}" ]; then
    ON_THING="on \"${OPTIONAL_THING}\""
  fi
}

displayLine() {
  MIN=$(($1 / 60))
  SEC=$(($1 % 60))
  optionalDescription "$2"
  printf "$3" $MIN $SEC "$ON_THING"
}

startPomodoro() {
  THING=$1
  NOW=$($DATE +"$DATE_FORMAT")
  mkdir -p "${LOG%/*}"
  echo "$NOW,,$THING" >> "$LOG"
  optionalDescription "$THING"
  echo "Pomodoro started $ON_THING"
}

waitForCompletion() {
  TICK_COMMAND="$1"
  COMPLETED_COMMAND="$2"
  while myCheckLastPomodoro; do
      REMAINING=$((POMODORO_LENGTH_IN_SECONDS - SECONDS_ELAPSED))
      displayLine $REMAINING "$THING" "\r$PREFIX %02d:%02d %s"

      if [ -n "$TICK_COMMAND" ]; then
        ( $TICK_COMMAND ) &
      fi
      sleep 1
  done
  if [ -n "$COMPLETED_COMMAND" ]; then
    ( $COMPLETED_COMMAND ) &
  fi
}

showStatus() {
  myCheckLastPomodoro
  retval="$?"
  if [ "$retval" -eq "0" ]; then
      REMAINING=$((POMODORO_LENGTH_IN_SECONDS - SECONDS_ELAPSED))
      displayLine $REMAINING "$THING" "$PREFIX %02d:%02d %s"
  elif [ "$retval" -eq "1" ]; then
      BREAK=$((SECONDS_ELAPSED - POMODORO_LENGTH_IN_SECONDS))
      if [ $BREAK -lt $POMODORO_BREAK_IN_SECONDS ]; then
        displayLine $BREAK "$THING" "$PREFIX Completed %02d:%02d ago %s"
      else
        LAST=$(convertTimeFormat "$TIME" "+%a, %d %b %Y %T")
        printf "Most recent pomodoro: $LAST"
      fi
  fi
}

usage() {
    cat <<EOF
usage: p [command]

Available commands:
   status (default)         Shows information about the current pomodoro
   start [description]      Starts a new pomodoro, cancelling any in progress
   cancel                   Cancels any pomodoro in progress
   internal                 Records an internal interruption on current pomodoro
   external                 Records an external interruption on current pomodoro
   wait [command]           Prints ticking counter and blocks until pomodoro completion.
                            Optionally runs 'command' every second
   loop <tick> <end>        Prints ticker and runs 'tick' every second and 'end' at
                            completion. Blocks until next pomodoro starts.
   log                      Shows pomodoro log output in CSV format
   help                     Prints this help text

Most commands may be shortened to their first letter. For more information
see http://github.com/chrismdp/p.
EOF
}

case "$1" in
  start | s)
    cancelRunningPomodoro "Last Pomodoro cancelled"
    shift
    startPomodoro "$@"
    ;;
  cancel | c)
    cancelRunningPomodoro "Cancelled. The next Pomodoro will go better!"
    ;;
  internal | i)
    interrupt $INTERNAL_INTERRUPTION_MARKER
    ;;
  external | e)
    interrupt $EXTERNAL_INTERRUPTION_MARKER
    ;;
  wait | w)
    shift
    waitForCompletion "$@" ""
    ;;
  loop)
    while true; do
      printf "\r                                                               "
      waitForCompletion "$2" "$3"
      printf "\r"
      showStatus
      sleep 1
    done
    ;;
  log | l)
    cat "$LOG"
    ;;
  help | h | -h)
    usage
    ;;
  status | *)
    showStatus
    printf "\n"
    ;;
esac
