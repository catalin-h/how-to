#!/bin/sh

printf "[ppid:$PPID, pid:$$] $TITLE\n"
printf " cgroup.events.%s\n" "$(grep 'populated' $1/cgroup.events)"

# Don't read the file with cat since it creates a new process that will be added
# to the cgroup process list
while read -r line; do
  plist="$plist$line "
done < $1/cgroup.procs
printf " cgroup.procs: %s\n" "$plist"

printf " cgroup: %s\n" "$(cat /proc/$$/cgroup)"

