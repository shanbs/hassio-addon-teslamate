#!/usr/bin/env bashio

# The script assumes that basic authentication is configured
#
# DASHBOARDS_DIRECTORY represents the path to the directory
# where the JSON files corresponding to the dashboards exist.
# The default location is relative to the execution of the
# script.
#
# Source: https://github.com/cirocosta/sample-grafana/blob/master/update-dashboards.sh

set -o errexit

readonly HOST=$(bashio::config 'grafana_host')
readonly PORT=$(bashio::config 'grafana_port')
readonly USER=$(bashio::config 'grafana_user')
readonly PASS=$(bashio::config 'grafana_pass')
readonly DASHBOARDS_DIRECTORY="/dashboards"
readonly FOLDER_NAME=$(bashio::config 'grafana_folder_name')



main() {
  local task=$1

  URL="https://$HOST:$PORT"
  LOGIN="$USER:$PASS"
  
  case $task in
      backup) backup;;
      restore) restore;;
      *)     exit 1;;
  esac

}


backup() {
  local dashboard_json

  for dashboard in $(list_dashboards); do
    dashboard_json=$(get_dashboard "$dashboard")

    if [[ -z "$dashboard_json" ]]; then
      echo "ERROR:
  Couldn't retrieve dashboard $dashboard.
      "
      exit 1
    fi

    echo "$dashboard_json" > "$DASHBOARDS_DIRECTORY/$dashboard".json

    echo "BACKED UP $(basename "$dashboard").json"
  done
}


restore() {
  bashio::log.info "Checking for Grafana folder: $FOLDER_NAME"
  FLD=$(curl --silent --show-error \
    --user "$LOGIN" -H "Content-Type: application/json" \
    $URL/api/folders | jq ".[] | select(.title==\"$FOLDER_NAME\")")
  
  if [[ -z "$FLD" ]]; then
    bashio::log.info "Not found... creating"
    FLD=$(curl \
          --silent \
          --show-error  \
          --user "$LOGIN" \
          -X POST -H "Content-Type: application/json" \
          -d "{\"title\":\"$FOLDER_NAME\"}" \
          "$URL/api/folders")
  fi

  FOLDER_ID=$(echo $FLD | jq -r .id)

  if [[ -z "$FOLDER_ID" ]]; then
    bashio::log.error "Could not determine Grafana folder id"
    exit 1
  fi

  find "$DASHBOARDS_DIRECTORY" -type f -name \*.json -print0 |
      while IFS= read -r -d '' dashboard; do
          curl \
            --silent --show-error --output /dev/null \
            --user "$LOGIN" \
            -X POST -H "Content-Type: application/json" \
            -d "{\"dashboard\":$(cat "$dashboard"),\"overwrite\":true,\"folderId\":$FOLDER_ID, \
                    \"inputs\":[{\"name\":\"DS_POSTGRES\",\"type\":\"datasource\", \
                    \"pluginId\":\"postgres\",\"value\":\"TeslaMate\"}]}" \
            "$URL/api/dashboards/import"

        bashio::log.info "... RESTORED $(basename "$dashboard")"
      done
  bashio::log.info "Finished Importing Grafana Dashboards"
}


get_dashboard() {
  local dashboard=$1

  if [[ -z "$dashboard" ]]; then
    echo "ERROR:
  A dashboard must be specified.
  "
    exit 1
  fi

  curl \
    --silent \
    --user "$LOGIN" \
    "$URL/api/dashboards/db/$dashboard" |
    jq '.dashboard | .id = null'
}


list_dashboards() {
  curl \
    --silent \
    --user "$LOGIN" \
    "$URL/api/search" |
    jq -r '.[] | select(.type == "dash-db") | .uri' |
    cut -d '/' -f2
}


main "$@"
