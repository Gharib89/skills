# Azure DevOps cloud-sandbox probe: https://dev.azure.com/ITWORXDevOps/AI_And_Data_Practice/_git/ship-ado-lab, 2026-09-09T05:20:36Z

## Environment

```
az:   2.90.0	2.90.0	1.1.0	
jq:   jq-1.8.1
curl: curl 8.18.0 (x86_64-pc-linux-gnu) libcurl/8.18.0 OpenSSL/3.5.5 zlib/1.3.1 brotli/1.2.0 zstd/1.5.7 libidn2/2.3.8 libpsl/0.21.2 libssh2/1.11.1 nghttp2/1.68.0 librtmp/2.3 mit-krb5/1.22.1 OpenLDAP/2.6.10
git:  git version 2.53.0
python3: Python 3.14.4
user: ribo uid=1000; HOME=/home/ribo; pwd=/home/ribo/wip/projects/skills
AZURE_DEVOPS_EXT_PAT set: yes
proxy env: HTTPS_PROXY=empty HTTP_PROXY=empty NO_PROXY=empty
dev.azure.com in NO_PROXY: no
```

### Reachability of the install hosts (curl, before any install)

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| curl aka.ms/InstallAzureCLIDeb | allowed |  |  | 1270 |
| curl azurecliprod.blob.core.windows.net | allowed |  |  | 969 |
| curl packages.microsoft.com | allowed |  |  | 117 |
| curl pypi.org | allowed |  |  | 282 |

az mode: **preinstalled**

### azure-devops extension

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| az extension add azure-devops | skipped |  | already present | 0 |

adapter rows below run against az: **true**

### Network: ADO REST over curl with the PAT (runs regardless of az)

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| GET _apis/connectionData | allowed |  |  | 264 |
| GET vssps profile/profiles/me | allowed |  |  | 551 |
| GET _apis/projects | allowed |  |  | 428 |
| GET git/repositories/{r} | allowed |  |  | 316 |
| POST wit/wiql (host_issues_ready twin) | allowed |  |  | 302 |
| GET git/pullrequests | allowed |  |  | 406 |

identity from connectionData: `Ahmed.Gharib@itworx.com`

### host_identity

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| az account show --query user.name (Entra path) | allowed |  |  | 296 |
| az devops invoke core connectionData (adapter PAT fallback) | failed |  | rc=1 ERROR: --resource and --api-version combination is not correct  | 1700 |

host_identity resolved to: `Ahmed.Gharib@itworx.com` (curl connectionData twin resolved `Ahmed.Gharib@itworx.com`)

### Work items (host_issue_*)

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| az boards work-item create (User Story) | allowed |  |  | 1189 |
| az boards work-item show --expand relations | allowed |  |  | 1004 |
| az devops invoke wit comments 7.1-preview | allowed |  |  | 1674 |
| az boards work-item update --discussion | allowed |  |  | 1979 |
| az boards work-item update --assigned-to | allowed |  |  | 1231 |
| az boards work-item update Tags (add) | allowed |  |  | 1030 |
| az boards work-item update Tags (remove one) | allowed |  |  | 1098 |
| az rest json-patch remove Tags (Entra-only path) | allowed |  |  | 643 |
| curl json-patch remove Tags (PAT twin) | allowed |  |  | 928 |
| az boards query --wiql (host_issues_ready) | allowed |  |  | 1104 |
| az boards work-item update --fields System.AssignedTo= (unassign) | allowed |  |  | 1269 |

### Git over the proxy (dev.azure.com, PAT over HTTPS)

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| git ls-remote (ADO) | allowed |  |  | 212 |
| git clone (ADO) | allowed |  |  | 585 |
| git push base branch | allowed |  |  | 495 |
| git push head branch | allowed |  |  | 804 |

### Pull requests (host_pr_*)

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| az repos pr create (non-draft, --work-items) | allowed |  |  | 1410 |
| az repos pr show | allowed |  |  | 1213 |
| az repos pr list --source-branch | allowed |  |  | 1215 |
| az repos pr policy list | allowed |  |  | 1766 |
| az devops invoke git pullRequestStatuses | allowed |  |  | 1897 |
| az devops invoke git pullRequestIterations | allowed |  |  | 1830 |
| az devops invoke git pullRequestThreads (read) | allowed |  |  | 1760 |
| az devops invoke git pullRequestThreads (POST, host_pr_comment) | allowed |  |  | 2124 |
| az devops invoke git pullRequestThreads (PATCH, resolve-thread) | allowed |  |  | 1655 |
| az repos pr reviewer list | allowed |  |  | 1107 |
| az repos pr reviewer add (self, expect rejection) | allowed |  |  | 1745 |
| az repos pr update --description | allowed |  |  | 1167 |

### Merge

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| az repos pr update --status completed --squash --transition-work-items | allowed |  |  | 1353 |
| az repos pr show after completion | allowed |  |  | 1453 |

PR 50576 final status: `completed`

### Teardown: ref deletion both ways, scratch work item

| call | verdict | http | detail | ms |
|---|---|---|---|---|
| git push --delete (git path) | allowed |  |  | 461 |
| POST git/refs (delete base, REST path) | allowed |  |  | 474 |
| az boards work-item update --state Closed | allowed |  |  | 1041 |
| az boards work-item delete | allowed |  |  | 1262 |

scratch: work item 221491, PR 50576, branches probe/base-1788931236 probe/head-1788931236 probe/del-1788931236; still on remote: none
