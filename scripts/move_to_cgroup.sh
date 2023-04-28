#!/bin/sh

printf "[ppid:$PPID, pid:$$] Using cgroup: %s\n" "$1"

# Use the dot command (. ./script.sh) to call the script
# on the same process and use TITLE variable to pass the title
TITLE="Before move"
. ./cgroup_stats.sh 

# Migrate to cgroup
printf "Migrating $$ to cgroup ...\n"
printf "$$" > $1/cgroup.procs

# Check the cgroup info
TITLE="After move"
. ./cgroup_stats.sh

# Launch a child process to check the assigned cgroup on startup
# Note that the TITLE set is part of the command in order to create
# the envar in the child process evironment.
TITLE="Child" ./cgroup_stats.sh $1

