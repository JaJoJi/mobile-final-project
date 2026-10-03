#!/usr/bin/env bash
# Writes infra/jenkins/plugins.txt (plugin:version, one per line) from the
# running Jenkins, so the plugin set is pinned in git (#288) and a rebuilt
# controller can install exactly these with:
#   jenkins-plugin-cli --latest=false -f infra/jenkins/plugins.txt
#
# Needs a Jenkins API token (Manage Jenkins > Users > you > Security).
# The token is read from the environment, never from argv:
#   JENKINS_URL=https://mfp-jenkins-psu.malaysiawest.cloudapp.azure.com \
#   JENKINS_USER=<you> JENKINS_TOKEN=<api-token> infra/jenkins/export-plugins.sh
set -euo pipefail
: "${JENKINS_URL:?set JENKINS_URL}" "${JENKINS_USER:?set JENKINS_USER}" "${JENKINS_TOKEN:?set JENKINS_TOKEN}"
out="$(dirname "$(readlink -f "$0")")/plugins.txt"
curl -g -fsS --netrc-file <(printf 'machine %s login %s password %s\n' \
    "$(echo "$JENKINS_URL" | sed -E 's#https?://([^/:]+).*#\1#')" "$JENKINS_USER" "$JENKINS_TOKEN") \
  "${JENKINS_URL%/}/pluginManager/api/json?depth=1&tree=plugins[shortName,version]" \
  | python3 -c "import json,sys; [print(p['shortName']+':'+p['version']) for p in sorted(json.load(sys.stdin)['plugins'], key=lambda p: p['shortName'])]" \
  > "$out"
echo "wrote $out ($(wc -l < "$out") plugins)"
