#!/usr/bin/env bash
# Probe: can a Claude Code on the web sandbox reach Azure DevOps, and does the
# proxy pass every call ship's ADO adapter (skills/ship/scripts/host/ado.sh)
# makes? Twin of docs/research/probe-gh-proxy.sh; same row shape:
#   name | allowed|blocked|api-error|failed|skipped | http | detail | ms
#
# Three layers, measured separately, because they fail independently:
#   1. Tooling  — can `az` and the azure-devops extension be obtained at all?
#   2. Network  — does the proxy pass dev.azure.com? Answered by the curl REST
#                 twins, which run even when `az` could not be installed.
#   3. Adapter  — every `az` call ado.sh makes, against real scratch objects.
#
# Any HTTP 403 with no ADO error body is `blocked`: the PAT is repo-owner grade,
# so a bare 403 here is the proxy's, not Azure's.
#
# Credential: AZURE_DEVOPS_EXT_PAT. The unattended cloud lane has no interactive
# login, so a PAT is the credential under test; `az login --use-device-code` is
# the attended fallback and is out of scope here. The PAT is never printed:
# every stderr line is scrubbed before it reaches the log.
#
# Scratch objects only, in the ship-ado-lab repo: one scratch work item, one PR
# from probe/head-* into probe/base-* (never main, which is policy-protected),
# torn down at the end. If scratch creation fails, the write rows are skipped.
set -u
TS=$(date +%s)
ORG_URL=${PROBE_ORG_URL:-https://dev.azure.com/ITWORXDevOps}
PROJECT=${PROBE_PROJECT:-AI_And_Data_Practice}
REPO=${PROBE_REPO:-ship-ado-lab}
WIT=${PROBE_WIT:-User Story}          # Agile process; Basic would be Issue
CLOSED=${PROBE_CLOSED:-Closed}        # Agile process; Basic would be Done
LOG=${PROBE_LOG:-probe-ado-proxy-results.md}
WORK=${PROBE_WORK:-/tmp/probe-ado-$TS}
PAT=${AZURE_DEVOPS_EXT_PAT:-}
ORG=(--org "$ORG_URL"); PRJ=("${ORG[@]}" --project "$PROJECT")
PROJ_ENC=$(jq -rn --arg p "$PROJECT" '$p | @uri')
API="$ORG_URL/$PROJ_ENC/_apis"
: >"$LOG"
# Absolute: the git rows cd into the scratch clone, and a relative tee would
# then start a second log there.
LOG="$(cd "$(dirname "$LOG")" && pwd)/$(basename "$LOG")"
row() { printf '| %s | %s | %s | %s | %s |\n' "$@" | tee -a "$LOG"; }
hdr() { printf '\n### %s\n\n| call | verdict | http | detail | ms |\n|---|---|---|---|---|\n' "$1" | tee -a "$LOG"; }
note() { printf '\n%s\n' "$*" | tee -a "$LOG"; }
OUT=""
# uutils coreutils ignores the width in %3N, so divide %s%N instead (defect found
# in the GitHub probe's control run).
ms() { local n; n=$(date +%s%N); echo $(( n / 1000000 )); }
# The PAT must never reach the log, however a tool chooses to echo it back.
scrub() { if [ -n "$PAT" ]; then sed -e "s|$PAT|****|g" -e "s|$(printf ':%s' "$PAT" | base64 -w0)|****|g"; else cat; fi; }
probe() {
  local name=$1; shift
  local err t0 t1 rc http detail verdict
  t0=$(ms)
  OUT=$("$@" 2>/tmp/probe-err); rc=$?
  t1=$(ms)
  err=$(scrub </tmp/probe-err | head -c 400 | tr '\n' ' ')
  http=$(grep -oE 'HTTP[ /][0-9.]* ?[0-9]{3}|[Ss]tatus[ :]+[0-9]{3}|error: [0-9]{3}' <<<"$err" | grep -oE '[0-9]{3}' | head -1)
  if [ $rc -eq 0 ]; then verdict=allowed; detail="";
  elif [ "${http:-}" = 403 ] && ! grep -qi 'TF[0-9]\|VS[0-9]\|azure devops' <<<"$err"; then verdict=blocked; detail=$err;
  elif [ -n "$http" ]; then verdict=api-error; detail=$err;
  else verdict=failed; detail="rc=$rc $err"; fi
  row "$name" "$verdict" "${http:-}" "${detail//|/\\|}" "$((t1-t0))"
}
# curl against the ADO REST API with the PAT as Basic auth. Prints the body on
# 2xx; on anything else prints "HTTP <code> <body head>" to stderr and fails,
# so probe() classifies it the same way it classifies az.
rest() { # <method> <url> [json-body] [content-type]
  local m=$1 url=$2 body=${3:-} ct=${4:-application/json} resp code
  resp=$(curl -sS -X "$m" -u ":$PAT" -H "Accept: application/json" \
    ${body:+-H "Content-Type: $ct" --data-binary "$body"} -w '\n%{http_code}' "$url") || return 1
  code=${resp##*$'\n'}; resp=${resp%$'\n'*}
  case $code in
    2*) printf '%s\n' "$resp";;
    *) echo "HTTP $code $(head -c 200 <<<"$resp" | tr '\n' ' ')" >&2; return 1;;
  esac
}
azx() { az "$@" -o json; }

{
echo "# Azure DevOps cloud-sandbox probe: $ORG_URL/$PROJECT/_git/$REPO, $(date -u +%FT%TZ)"
echo
echo '## Environment'
echo
echo '```'
echo "az:   $(command -v az >/dev/null && az version --output tsv 2>/dev/null | head -1 || echo MISSING)"
echo "jq:   $(command -v jq >/dev/null && jq --version || echo MISSING)"
echo "curl: $(curl --version 2>/dev/null | head -1 || echo MISSING)"
echo "git:  $(git --version)"
echo "python3: $(command -v python3 >/dev/null && python3 --version 2>&1 || echo MISSING)"
echo "user: $(id -un) uid=$(id -u); HOME=$HOME; pwd=$(pwd)"
echo "AZURE_DEVOPS_EXT_PAT set: $([ -n "$PAT" ] && echo yes || echo NO)"
echo "proxy env: HTTPS_PROXY=$([ -n "${HTTPS_PROXY:-}" ] && echo set || echo empty) HTTP_PROXY=$([ -n "${HTTP_PROXY:-}" ] && echo set || echo empty) NO_PROXY=$([ -n "${NO_PROXY:-}" ] && echo set || echo empty)"
echo "dev.azure.com in NO_PROXY: $(grep -qi 'dev\.azure\.com\|azure\.com' <<<"${NO_PROXY:-}" && echo yes || echo no)"
echo '```'
} | tee -a "$LOG"

[ -n "$PAT" ] || { note "**AZURE_DEVOPS_EXT_PAT is empty. Nothing below can run.** Set it and re-run."; exit 2; }

# ---- 1. Tooling: can az be obtained? ---------------------------------------
hdr "Reachability of the install hosts (curl, before any install)"
probe "curl aka.ms/InstallAzureCLIDeb"            curl -fsS -o /dev/null -L https://aka.ms/InstallAzureCLIDeb
probe "curl azurecliprod.blob.core.windows.net"   curl -fsS -o /dev/null 'https://azurecliprod.blob.core.windows.net/$root/deb_install.sh'
probe "curl packages.microsoft.com"               curl -fsS -o /dev/null -I https://packages.microsoft.com/keys/microsoft.asc
probe "curl pypi.org"                             curl -fsS -o /dev/null -I https://pypi.org/simple/azure-cli/

AZ_MODE=preinstalled
if ! command -v az >/dev/null; then
  hdr "az install attempts (ship's tooling --install and its fallbacks)"
  SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo -n"
  # What host_tooling_install actually runs today.
  probe "curl aka.ms/InstallAzureCLIDeb | bash" bash -c "curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash"
  if ! command -v az >/dev/null; then
    # The currently documented one-liner; aka.ms is a redirect to it.
    probe "curl azurecliprod deb_install.sh | bash" bash -c "curl -fsSL 'https://azurecliprod.blob.core.windows.net/\$root/deb_install.sh' | $SUDO bash"
  fi
  if ! command -v az >/dev/null; then
    probe "apt-get install azure-cli (distro repo)" bash -c "$SUDO apt-get update -qq >/dev/null && $SUDO apt-get install -y -qq azure-cli >/dev/null && command -v az"
  fi
  if ! command -v az >/dev/null; then
    probe "pip install azure-cli" bash -c "python3 -m pip install --quiet --break-system-packages azure-cli >/dev/null 2>&1 && command -v az || { export PATH=\$HOME/.local/bin:\$PATH; command -v az; }"
    export PATH="$HOME/.local/bin:$PATH"
  fi
  command -v az >/dev/null && AZ_MODE=installed || AZ_MODE=missing
fi
note "az mode: **$AZ_MODE**"

if [ "$AZ_MODE" != missing ]; then
  hdr "azure-devops extension"
  if az extension show --name azure-devops >/dev/null 2>&1; then
    row "az extension add azure-devops" skipped "" "already present" 0
  else
    probe "az extension add --name azure-devops" az extension add --name azure-devops --only-show-errors
  fi
fi
AZ_OK=false
command -v az >/dev/null && az extension show --name azure-devops >/dev/null 2>&1 && AZ_OK=true
note "adapter rows below run against az: **$AZ_OK**"

# ---- 2. Network: REST twins, independent of az -----------------------------
hdr "Network: ADO REST over curl with the PAT (runs regardless of az)"
probe "GET _apis/connectionData"  rest GET "$ORG_URL/_apis/connectionData?api-version=7.1-preview"
ME_REST=$(jq -r '.authenticatedUser.properties.Account."$value" // .authenticatedUser.uniqueName // empty' <<<"${OUT:-}" 2>/dev/null)
# vssps, a different host than dev.azure.com: worth its own row, because a
# proxy allowlist can pass one and not the other.
probe "GET vssps profile/profiles/me" rest GET "https://vssps.dev.azure.com/${ORG_URL##*/}/_apis/profile/profiles/me?api-version=7.1-preview.3"
probe "GET _apis/projects"        rest GET "$ORG_URL/_apis/projects?api-version=7.1"
probe "GET git/repositories/{r}"  rest GET "$API/git/repositories/$REPO?api-version=7.1"
WIQL="SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.State] <> '$CLOSED' ORDER BY [System.CreatedDate] ASC"
probe "POST wit/wiql (host_issues_ready twin)" rest POST "$API/wit/wiql?api-version=7.1" "$(jq -cn --arg q "$WIQL" '{query: $q}')"
probe "GET git/pullrequests"      rest GET "$API/git/repositories/$REPO/pullrequests?searchCriteria.status=active&api-version=7.1"
note "identity from connectionData: \`${ME_REST:-unresolved}\`"

# ---- 3. Adapter: every az call ado.sh makes --------------------------------
export AZURE_DEVOPS_EXT_PAT="$PAT"
ME=""
if $AZ_OK; then
  hdr "host_identity"
  # Entra path first, as the adapter does; a PAT session has no `az account`.
  probe "az account show --query user.name (Entra path)" az account show --query user.name -o tsv
  ME=$(head -1 <<<"${OUT:-}" | tr -d '"')
  # The adapter's PAT fallback, exactly as ado.sh writes it. The control run on
  # 2026-09-09 failed this at every api-version tried, so the row is expected to
  # fail and the curl twin below is what a PAT-only session would need.
  probe "az devops invoke core connectionData (adapter PAT fallback)" \
    azx devops invoke "${ORG[@]}" --http-method GET --area core --resource connectionData --api-version 7.1
  [ -n "$ME" ] || ME=$(jq -r '.authenticatedUser.properties.Account."$value" // .authenticatedUser.uniqueName // empty' <<<"${OUT:-}" 2>/dev/null)
  ME=${ME:-$ME_REST}
  note "host_identity resolved to: \`${ME:-unresolved}\` (curl connectionData twin resolved \`${ME_REST:-nothing}\`)"
fi

WI=""
if $AZ_OK; then
  hdr "Work items (host_issue_*)"
  probe "az boards work-item create ($WIT)" \
    azx boards work-item create "${PRJ[@]}" --type "$WIT" --title "probe: ado proxy $TS (scratch, auto-closed)" \
        --description "<pre>Scratch work item for wayfinder ticket 29. Safe to delete.</pre>" --fields "System.Tags=probe-scratch"
  WI=$(jq -r '.id // empty' <<<"${OUT:-}" 2>/dev/null)
  if [ -n "$WI" ]; then
    probe "az boards work-item show --expand relations" azx boards work-item show "${ORG[@]}" --id "$WI" --expand relations
    probe "az devops invoke wit comments 7.1-preview"  azx devops invoke "${ORG[@]}" --http-method GET --area wit --resource comments \
      --api-version 7.1-preview --route-parameters project="$PROJECT" workItemId="$WI"
    probe "az boards work-item update --discussion"    azx boards work-item update "${ORG[@]}" --id "$WI" --discussion "probe discussion $TS"
    [ -n "$ME" ] && probe "az boards work-item update --assigned-to" azx boards work-item update "${ORG[@]}" --id "$WI" --assigned-to "$ME" \
                 || row "az boards work-item update --assigned-to" skipped "" "no identity resolved" 0
    probe "az boards work-item update Tags (add)"      azx boards work-item update "${ORG[@]}" --id "$WI" --fields "System.Tags=probe-scratch; ready-for-agent"
    probe "az boards work-item update Tags (remove one)" azx boards work-item update "${ORG[@]}" --id "$WI" --fields "System.Tags=probe-scratch"
    # host_issue_remove_label's last-tag path: az rest on an Entra token. A
    # PAT-only session is expected to fail this; the REST twin below is the
    # measurement that matters for the cloud lane.
    probe "az rest json-patch remove Tags (Entra-only path)" \
      az rest --method patch --url "$ORG_URL/_apis/wit/workitems/$WI?api-version=7.1" \
        --resource 499b84ac-1321-427f-aa17-267ca6975798 --headers "Content-Type=application/json-patch+json" \
        --body '[{"op":"remove","path":"/fields/System.Tags"}]' -o none
    probe "curl json-patch remove Tags (PAT twin)" \
      rest PATCH "$ORG_URL/_apis/wit/workitems/$WI?api-version=7.1" '[{"op":"remove","path":"/fields/System.Tags"}]' application/json-patch+json
    probe "az boards query --wiql (host_issues_ready)" \
      azx boards query "${PRJ[@]}" --wiql "SELECT [System.Id], [System.Title] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.State] <> '$CLOSED' AND [System.Tags] CONTAINS 'ready-for-agent' AND [System.AssignedTo] = '' ORDER BY [System.CreatedDate] ASC"
    probe "az boards work-item update --fields System.AssignedTo= (unassign)" \
      azx boards work-item update "${ORG[@]}" --id "$WI" --fields "System.AssignedTo="
  else
    note "Scratch work item creation failed: the work-item write rows and the PR link are skipped."
  fi
fi

# ---- git over the proxy ----------------------------------------------------
hdr "Git over the proxy (dev.azure.com, PAT over HTTPS)"
CLONE_URL="$ORG_URL/$PROJ_ENC/_git/$REPO"
AUTH_HDR="AUTHORIZATION: Basic $(printf ':%s' "$PAT" | base64 -w0)"
# ship-ado-lab enforces a commit-author policy (VS403702 on the control run), so
# the scratch commit is authored by the resolved identity, not a placeholder.
AUTHOR=${ME:-${ME_REST:-probe@example.invalid}}
G=(git -c "http.extraheader=$AUTH_HDR" -c credential.helper= -c user.name=probe -c "user.email=$AUTHOR")
probe "git ls-remote (ADO)"  "${G[@]}" ls-remote --heads "$CLONE_URL" main
mkdir -p "$WORK"
probe "git clone (ADO)"      "${G[@]}" clone -q "$CLONE_URL" "$WORK/repo"
BASE=probe/base-$TS; HEAD=probe/head-$TS; SHA=""
if [ -d "$WORK/repo/.git" ]; then
  cd "$WORK/repo" || exit 1
  G=(git -c "http.extraheader=$AUTH_HDR" -c credential.helper= -c user.name=probe -c "user.email=$AUTHOR")
  git branch -f "$BASE" HEAD >/dev/null 2>&1
  probe "git push base branch" "${G[@]}" push -q origin "$BASE"
  git checkout -q -b "$HEAD" >/dev/null 2>&1
  echo "probe $TS" > "probe-$TS.txt"; git add "probe-$TS.txt"
  "${G[@]}" commit -qm "probe: scratch commit $TS" >/dev/null 2>&1
  probe "git push head branch" "${G[@]}" push -q origin "$HEAD"
  SHA=$(git rev-parse HEAD 2>/dev/null)
else
  note "Clone failed: every git and pull-request row below is skipped."
fi

# ---- pull requests ---------------------------------------------------------
PR=""
if $AZ_OK && [ -n "$SHA" ]; then
  hdr "Pull requests (host_pr_*)"
  probe "az repos pr create (non-draft, --work-items)" \
    azx repos pr create "${PRJ[@]}" --repository "$REPO" --source-branch "$HEAD" --target-branch "$BASE" \
      --title "probe: scratch PR $TS" --description "Scratch PR for wayfinder ticket 29." --draft false ${WI:+--work-items "$WI"}
  PR=$(jq -r '.pullRequestId // empty' <<<"${OUT:-}" 2>/dev/null)
  if [ -n "$PR" ]; then
    probe "az repos pr show"                 azx repos pr show "${ORG[@]}" --id "$PR"
    probe "az repos pr list --source-branch" azx repos pr list "${PRJ[@]}" --repository "$REPO" --source-branch "$HEAD" --status all --top 1
    probe "az repos pr policy list"          azx repos pr policy list "${ORG[@]}" --id "$PR"
    probe "az devops invoke git pullRequestStatuses" azx devops invoke "${ORG[@]}" --http-method GET --area git --resource pullRequestStatuses \
      --api-version 7.1 --route-parameters project="$PROJECT" repositoryId="$REPO" pullRequestId="$PR"
    probe "az devops invoke git pullRequestIterations" azx devops invoke "${ORG[@]}" --http-method GET --area git --resource pullRequestIterations \
      --api-version 7.1 --route-parameters project="$PROJECT" repositoryId="$REPO" pullRequestId="$PR"
    probe "az devops invoke git pullRequestThreads (read)" azx devops invoke "${ORG[@]}" --http-method GET --area git --resource pullRequestThreads \
      --api-version 7.1 --route-parameters project="$PROJECT" repositoryId="$REPO" pullRequestId="$PR"
    TF=$(mktemp); jq -n '{comments: [{parentCommentId: 0, content: "probe thread", commentType: 1}], status: "closed"}' > "$TF"
    probe "az devops invoke git pullRequestThreads (POST, host_pr_comment)" azx devops invoke "${ORG[@]}" --http-method POST --area git --resource pullRequestThreads \
      --api-version 7.1 --route-parameters project="$PROJECT" repositoryId="$REPO" pullRequestId="$PR" --in-file "$TF"
    TID=$(jq -r '.id // empty' <<<"${OUT:-}" 2>/dev/null); rm -f "$TF"
    if [ -n "$TID" ]; then
      TF=$(mktemp); printf '{"status":"fixed"}' > "$TF"
      probe "az devops invoke git pullRequestThreads (PATCH, resolve-thread)" azx devops invoke "${ORG[@]}" --http-method PATCH --area git --resource pullRequestThreads \
        --api-version 7.1 --route-parameters project="$PROJECT" repositoryId="$REPO" pullRequestId="$PR" threadId="$TID" --in-file "$TF"
      rm -f "$TF"
    else row "az devops invoke pullRequestThreads (PATCH)" skipped "" "no thread id from the POST" 0; fi
    probe "az repos pr reviewer list"     azx repos pr reviewer list "${ORG[@]}" --id "$PR"
    # Requesting the PR's own author: an ADO rejection here proves the call
    # passed with no side effect, the way the GitHub probe's 422 does.
    [ -n "$ME" ] && probe "az repos pr reviewer add (self, expect rejection)" azx repos pr reviewer add "${ORG[@]}" --id "$PR" --reviewers "$ME" \
                 || row "az repos pr reviewer add" skipped "" "no identity resolved" 0
    probe "az repos pr update --description" azx repos pr update "${ORG[@]}" --id "$PR" --description "Scratch PR for ticket 29. Body updated $TS."
    hdr "Merge"
    probe "az repos pr update --status completed --squash --transition-work-items" \
      azx repos pr update "${ORG[@]}" --id "$PR" --status completed --squash true --delete-source-branch true \
        --transition-work-items true --merge-commit-message "probe: scratch squash $TS"
    sleep 5
    probe "az repos pr show after completion" azx repos pr show "${ORG[@]}" --id "$PR"
    note "PR $PR final status: \`$(jq -r '.status // "unknown"' <<<"${OUT:-}" 2>/dev/null)\`"
  else
    note "No scratch PR: the pull-request and merge rows are skipped."
  fi
elif [ -n "$SHA" ]; then
  note "az unavailable: the pull-request rows are skipped. The REST twins above carry the network verdict."
fi

# ---- teardown --------------------------------------------------------------
hdr "Teardown: ref deletion both ways, scratch work item"
if [ -n "$SHA" ]; then
  # Completing the PR with --delete-source-branch already removed the head ref,
  # so deleting it here would record a false failure. Ref deletion is the point
  # of this section (the GitHub proxy refused it 403 both ways), so push a third
  # throwaway ref and delete that with git, and the base ref with REST.
  DEL=probe/del-$TS
  git branch -f "$DEL" HEAD >/dev/null 2>&1
  if "${G[@]}" push -q origin "$DEL" 2>/dev/null; then
    probe "git push --delete (git path)" "${G[@]}" push -q origin --delete "$DEL"
  else row "git push --delete (git path)" skipped "" "could not push the throwaway ref" 0; fi
  # REST twin of the deletion.
  OLD=$("${G[@]}" ls-remote --heads origin "$BASE" 2>/dev/null | awk '{print $1}')
  if [ -n "$OLD" ]; then
    probe "POST git/refs (delete base, REST path)" rest POST "$API/git/repositories/$REPO/refs?api-version=7.1" \
      "$(jq -cn --arg n "refs/heads/$BASE" --arg o "$OLD" '[{name: $n, oldObjectId: $o, newObjectId: "0000000000000000000000000000000000000000"}]')"
  else row "POST git/refs (delete base, REST path)" skipped "" "base ref already gone" 0; fi
  LEFT=$("${G[@]}" ls-remote --heads origin 'probe/*' 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
else LEFT="(clone failed)"; fi
if [ -n "$WI" ]; then
  if $AZ_OK; then
    probe "az boards work-item update --state $CLOSED" azx boards work-item update "${ORG[@]}" --id "$WI" --state "$CLOSED"
    probe "az boards work-item delete"                 azx boards work-item delete "${PRJ[@]}" --id "$WI" --yes
  else row "scratch work item cleanup" skipped "" "az unavailable" 0; fi
fi
note "scratch: work item ${WI:-none}, PR ${PR:-none}, branches $BASE $HEAD ${DEL:-}; still on remote: ${LEFT:-none}"
cd / 2>/dev/null; rm -rf "$WORK"
echo "results in $LOG"
