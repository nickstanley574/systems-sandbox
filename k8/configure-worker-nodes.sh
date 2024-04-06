#!/bin/bash -ex

# TODO: Race condition should change process to check
# for master cluster health before moving foward.
sleep 60

/root/join_command.sh