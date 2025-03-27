#!/usr/bin/env bash

set -m # allow for job control
set -x
EXIT_CODE=0;  # exit code of overall script

# may need to set -o posix if we run into issues with the for loop returning a 127 or bad_trap error

INPUT_CMD=$1

function handleJobs() {
     for job in `jobs -p`; do
         echo "PID => ${job}"
         CODE=0;
         wait ${job=$!} || CODE=$?
         if [[ "${CODE}" != "0" ]]; then
         echo "At least one test failed with exit code => ${CODE}" ;
         EXIT_CODE=1;
         fi
     done
}

function wait_and_get_exit_codes() {
    children=("$@")
    EXIT_CODE=0
    for job in "${children[@]}"; do
       echo "PID => ${job}"
       CODE=0;
       wait ${job} || CODE=$?
       if [[ "${CODE}" != "0" ]]; then
           echo "At least one test failed with exit code => ${CODE}" ;
           EXIT_CODE=1;
       fi
   done
}

# trap 'handleJobs' CHLD  # trap command is the key part
DIRN=$(dirname "$0");

commands=(
    "{ $INPUT_CMD; }"
)

clen=`expr "${#commands[@]}" - 1` # get length of commands - 1

# for i in `seq 0 "$clen"`; do
#     (echo "${commands[$i]}" | bash) &   # run the command via bash in subshell
#     echo "$INPUT_CMD has been issued as a background job"
# done

children_pids=()
for i in `seq 0 "$clen"`; do
    (echo "${commands[$i]}" | bash) &   # run the command via bash in subshell
    children_pids+=("$!")
    echo "$i ith command has been issued as a background job"
done
# wait; # wait for all subshells to finish - its still valid to wait for all jobs to finish, before processing any exit-codes if we wanted to
#EXIT_CODE=0;  # exit code of overall script
wait_and_get_exit_codes "${children_pids[@]}"

#wait; # wait for all subshells to finish

echo "EXIT_CODE => $EXIT_CODE"
exit "$EXIT_CODE"
# end

