#!/bin/bash
#
# provision-network-functions.sh
#
# This file is for common network helper functions that get called in
# other provisioners

export YELLOW="\033[38;5;3m"
export YELLOW_UNDERLINE="\033[4;38;5;3m"
export GREEN="\033[38;5;2m"
export RED="\033[38;5;9m"
export BLUE="\033[38;5;4m" # 33m"
export PURPLE="\033[38;5;5m" # 129m"
export CRESET="\033[0m"
export BOLD="\033[1m"

export VVV_CONFIG
export VVV_CURRENT_LOG_FILE=""


#override vagrant noroot function to make it do nothing
function noroot() {
  "$@";
}
export -f noroot


function get_config_value() {
  local value
  value=$(shyaml get-value "${1}" 2> /dev/null < "${VVV_CONFIG}")
  echo "${value:-$2}"
}
export -f get_config_value

function get_config_values() {
  local value
  value=$(shyaml get-values "${1}" 2> /dev/null < "${VVV_CONFIG}")
  echo "${value:-$2}"
}
export -f get_config_values
