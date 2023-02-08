#!/usr/bin/env bash

# filename          : appd_cfg_backup.sh
# description       : A script that does backups of AppDynamics Configuration.
#   Wrapper arround the Config Exporter API
# author            : Alexander Agbidinoukoun
# email             : aagbidin@cisco.com
# date              : 20230124
# version           : 0.3
# usage             : ./appd_cfg_backup.sh [-h] [-v] [-r "command"] -m export|import -c config_file
# notes             : 
#   0.1: first release
#   0.2: added oauth token authentication; added -r option to start the config exporter automatically
#   0.3: added dashboard exports + bug fixes
# 
#==============================================================================


set -Euo pipefail
trap cleanup SIGINT SIGTERM EXIT

PREV_IFS=$IFS

# check for jq
if ! command -v jq >/dev/null; then
  echo "Please install jq to use this tool (sudo yum install -y jq)"
  exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
log_file=$(echo ${BASH_SOURCE[0]} | sed 's/sh$/log/')
timestamp=$(date +%Y%m%d%H%M%S)
run_wait=10 # time to wait after running the config exporter
output_name_mode='name' # id|name

usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-r "command"] -m export|import -c config_file

Backup AppDynamics Configuration (Skandia).

Available options:

-h, --help        Print this help and exit
-v, --verbose     Print script debug info
-r, --run         Command to run the Config Exporter. Do not set if it is already running.
-m, --mode        Export or Import
-c, --config      Path to config file

EOF
  exit
}

setup_colors() {
  if [ -t 2 ] && [ -z "${NO_COLOR-}" ] && [ "${TERM-}" != "dumb" ]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[0;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

log() {
  echo >&2 -e "${1-}" >> ${log_file}
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  local date=`date '+%Y-%m-%d %H:%M:%S'`
  msg "${date}: ${RED}ERROR:${NOFORMAT} $msg"
  log "${date}: ERROR: $msg"
  exit $code
}

warn() {
  local msg=$1
  local date=`date '+%Y-%m-%d %H:%M:%S'`
  msg "${date}: ${YELLOW}WARN:${NOFORMAT} $msg"
  log "${date}: WARN: $msg"
}

info() {
  local msg=$1
  local date=`date '+%Y-%m-%d %H:%M:%S'`
  msg "${date}: ${GREEN}INFO:${NOFORMAT} $msg"
  log "${date}: INFO: $msg"
}

parse_params() {
  # default values of variables set from params

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -c | --config)
      config="${2-}"
      shift
      ;;
    -m | --mode)
      mode="${2-}"
      shift
      ;;
    -r | --run)
      run="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [ -z "${config-}" ] &&  warn "Missing required parameter: config" && usage
  [ -z "${mode-}" ] && warn "Missing required parameter: mode" && usage

  #[ ${#args[@]} -eq 0 ] && die "Missing script arguments"

  return 0
}

setup_colors

parse_params "$@"

# script logic here

cleanup() {
  trap - SIGINT SIGTERM EXIT
  # stop config exporter
  [ ! -z "${pid-}" ] && info "Stopping Config Exporter (pid = $pid)." && kill $pid
  # delete temporary file
  info "Cleaning up temporary files" 
  [ ! -z "${appd_cookie_path-}" ] && rm $appd_cookie_path
  info "Done."
}


my_curl() {
  auth=$1; shift

  x_csrf_header=''
  [ ! -z "${x_csrf_token-}" ] && x_csrf_header="-H X-CSRF-TOKEN:$x_csrf_token"

  if [ "$auth" == "true" -a ! -z "$appd_oauth_token" ]; then
    curl -s -H "Authorization:Bearer $appd_oauth_token" $appd_proxy "$@"
  elif [ "$auth" == "true" ]; then
    curl -s -u "${appd_api_user}@${appd_account}:${appd_api_password}" ${appd_proxy} --cookie $appd_cookie_path $x_csrf_header "$@"
  else
    curl -s "$@"
  fi
}

get_appd_oauth_token() {

  # curl request
  response=`my_curl true -X POST -H "Content-Type: application/vnd.appd.cntrl+protobuf;v=1" \
  -d "grant_type=client_credentials&client_id=${appd_api_user}@${appd_account}&client_secret=${appd_api_secret}" \
  ${appd_url}/controller/api/oauth/access_token`

  # validate response
  [ -z "`echo $response | grep access_token`" ] && die "Could not retrieve oauth token: $response"

  # extract token from response
  echo -n $response | sed 's/[[:blank:]]//g' | sed -E 's/^.*"access_token":"([^"]*)".*$/\1/'
}

get_appd_cookie() {
  # curl request
  my_curl true --cookie-jar $appd_cookie_path ${appd_url}/controller/auth?action=login
  
  x_csrf_token="`grep X-CSRF-TOKEN $appd_cookie_path | sed 's/^.*X-CSRF-TOKEN[[:blank:]]*\(.*\)$/\1/'`"

  # validate response
  [ -z "$x_csrf_token" ] && warn "Could not retrieve AppDynamics login cookie"
}

get_entities_info() {

  url=$1
  regex=$2
  response=`my_curl true $url`
  infos=`jq -r ".[] | select(.name | test(\"$regex\")) | .name,.id" <<<$response`

  app_infos=""
  last_info='id'

  PREV_IFS=$IFS
  IFS=$'\n'
  for info in ${infos}; do
    if [ `echo ${info} | grep -E '^[0-9]+$'` ] ; then  # app id
      app_infos+="=${info},"
      last_info='id'
    else
      if [ $last_info == 'id' ]; then # app name
        app_infos+="${info}"
      else # app name with space
        app_infos+=" ${info}"
      fi
      last_info='name'
    fi
  done
  IFS=$PREV_IFS

  echo -n ${app_infos}
}

get_applications_info() {
  get_entities_info "${appd_url}/controller/rest/applications?output=json" "$appd_application_names"
}

get_dashboards_info() {
  get_entities_info "${appd_url}/controller/restui/dashboards/getAllDashboardsByType/false" "$appd_dashboard_names"
}

export_dashboard() {
  name=$1
  id=$2
  
  [ $output_name_mode == "name" ] && output_file=${output_dir}/dashboards/${name}.json || output_file=${output_dir}/dashboards/${id}.json
  
  info "Exporting dashboard ${name}"
  my_curl true -o "${output_file}" "${appd_url}/CustomDashboardImportExportServlet?dashboardId=${id}"
}

export_dashboards() {

  info "*** Exporting dashboards"

  mkdir ${output_dir}/dashboards

  # retrieve dashboard names & ids from dashboard regex
  info "Retrieving AppDynamics dashboards details"
  dashboards_info=`get_dashboards_info`
  info "Matched dashboards: $dashboards_info"

  # loop over all dashboards
  PREV_IFS=$IFS
  IFS=','
  for info in ${dashboards_info}; do
    IFS=$PREV_IFS
    name=`echo ${info} | cut -d '=' -f 1`
    id=`echo ${info} | cut -d '=' -f 2`
    export_dashboard "$name" $id
    IFS=','
  done
  IFS=$PREV_IFS

  return 0
}

export_config_entity() {
  name=$1
  id=$2
  entity=$3
  
  [ $output_name_mode == "name" ] && output_file="${output_dir}/${name}/${entity}.json" || output_file="${output_dir}/${id}/${entity}.json"

  info "Exporting ${entity}"
  my_curl false -o "${output_file}" "${config_exporter_url}/api/controllers/${appd_id}/files/${entity}?applicationId=${id}"
  
  validate_config_output "$output_file"
  [ $? -ne 0 ] && warn "There was an issue exporting ${entity} for application $name ($id)" && return 1

  return 0
}

validate_config_output() {
  file=$1
  grep controllerUrl "$file" > /dev/null 2>&1
  return $?
}

export_account_config() {

  info "*** Exporting account level configuration"
  
  mkdir ${output_dir}/account

  # loop over all account config
  PREV_IFS=$IFS
  IFS=','
  for entity in ${appd_account_config}; do
    IFS=$PREV_IFS
    if [ $entity == "dashboards" ]; then
      export_dashboards
    else
      export_config_entity account account $entity
    fi
  IFS=','
  done 
  IFS=$PREV_IFS

  return 0
}

export_application_config() {
  
  # retrieve application names & ids from application regex
  info "Retrieving AppDynamics application details"
  applications_info=`get_applications_info`
  info "Matched applications: $applications_info"

  # loop over all applications
  PREV_IFS=$IFS
  IFS=','
  for info in ${applications_info}; do
    IFS=$PREV_IFS
    name=`echo ${info} | cut -d '=' -f 1`
    id=`echo ${info} | cut -d '=' -f 2`
    info "*** Exporting configuration for application $name ($id)"
    [ $output_name_mode == "name" ] && mkdir "${output_dir}/${name}" || mkdir ${output_dir}/${id}

    # loop over config entities
    IFS=','
    for entity in ${appd_application_config}; do
      IFS=$PREV_IFS
      export_config_entity "$name" $id $entity
      IFS=','
    done 
    IFS=','
  done
  IFS=$PREV_IFS

  return 0
}

get_controller_id() {
  regex=${appd_url}
  response=`my_curl false "${config_exporter_url}/api/controllers"`
  id=`jq -r ".[] | select(.url | test(\"$regex\")) | .id" <<<$response`
  echo $id
}


init() {

  # source config file
  [ ! -r $config ] && die "$config is not readable"
  . $config

  # check required config entries
  [ -z "${appd_url-}" ] && die "Missing required config entry: appd_url"
  [ -z "${appd_account-}" ] && die "Missing required config entry: appd_account"
  [ -z "${appd_api_user-}" ] && die "Missing required config entry: appd_api_user"
  [ -z "${appd_api_password-}" ] && [ -z "${appd_api_secret-}" ] && die "Missing required config entry: appd_api_password or appd_api_secret"
  [ -z "${appd_application_names-}" ] && die "Missing required config entry: appd_application_names"
  [ -z "${appd_dashboard_names-}" ] && die "Missing required config entry: appd_dashboard_names"
  [ -z "${output_dir-}" ] && die "Missing required config entry: output_dir"
  [ -z "${appd_application_config-}" ] && [ -z "${appd_account_config-}" ] && die "Missing required config entry: appd_application_config or appd_account_config"
  [ -z "${config_exporter_url-}" ] && die "Missing required config entry: config_exporter_url"
 
  # proxy
  appd_proxy=""
  [ ! -z "${appd_proxy-}" ] && appd_proxy="--proxy ${appd_proxy}"

  # display key config
  info "Using AppDynamics Source URL: ${appd_url-}"
  info "Using output directory: ${output_dir}"
  info "Using application name regex: ${appd_application_names}"
  info "Using dashboard name regex: ${appd_dashboard_names}"

  # create output dir if it does not exist
  if [ ! -d ${output_dir} ]; then 
    mkdir ${output_dir}
    [ $? -ne 0 ] && die "Could not create output directory: ${output_dir}"
  fi

  # create timestamp dir
  mkdir ${output_dir}/${timestamp}
  output_dir="${output_dir}/${timestamp}"

  # retrieve appd token
  appd_oauth_token=''
  if [ "${appd_api_secret}" != "" ]; then
    info "Retrieving AppDynamics oauth token at ${appd_url}"
    appd_oauth_token=`get_appd_oauth_token`
  fi
  
  # retrieve appd cookie and store it
  appd_cookie_path=${output_dir}/.appd_cookie
  info "Retrieving AppDynamics login cookie at ${appd_url}"
  get_appd_cookie

  # launch config exporter
  if [ ! -z "${run-}" ]; then
    info "Starting Config Exporter with command: ${run}"
    eval "nohup ${run} > /dev/null 2>&1 &"
    [ $? -ne 0 ] && die "Config Exporter command failed"
    pid=$!

    info "Waiting for Config Exporter to load..."
    for i in `seq 1 $run_wait`; do
      echo -n "."
      sleep 1
    done
    echo
    info "Config Exporter started (pid = $pid)."
    fi
  return 0
}

# main

init

if [ $mode == "export" ]; then
    info "Export Configuration: Start"
    info "Retrieving Controller id"
    appd_id=`get_controller_id`
    [ -z "$appd_id" ] && die "Could not retrieve the controller id via the Config Exporter API. Is ${appd_url} configured?"
    [ ! -z "${appd_application_config-}" ] && export_application_config
    [ ! -z "${appd_account_config-}" ] && export_account_config
    info "Export Configuration: Completed"
else
  die "Unknown mode: $mode"
fi