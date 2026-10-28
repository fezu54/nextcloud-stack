#!/bin/bash

# Separate management options from script arguments
mgmt_args=()
mute_args=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user|-h|--host|-p|--path|-i|--item|--folder)
            mgmt_args+=("$1" "$2")
            shift 2
            ;;
        -n|--new|--help)
            mgmt_args+=("$1")
            shift 1
            ;;
        *)
            mute_args+=("$1")
            shift 1
            ;;
    esac
done

# Call management script with the mute command
./manage.sh "${mgmt_args[@]}" mute "${mute_args[@]}"
