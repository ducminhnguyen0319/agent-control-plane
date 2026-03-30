#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../tools/bin/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_PR_PREFIXES_JSON="$(flow_managed_pr_prefixes_json "${CONFIG_YAML}")"
AGENT_PR_ISSUE_CAPTURE_REGEX="$(flow_managed_issue_branch_regex "${CONFIG_YAML}")"
MIN_AGE_MINUTES="${1:-30}"

open_agent_pr_issue_ids="$(
  gh pr list -R "$REPO_SLUG" --state open --limit 100 --json headRefName,body,labels,comments \
    | jq --argjson agentPrPrefixes "${AGENT_PR_PREFIXES_JSON}" --arg branchIssueRegex "${AGENT_PR_ISSUE_CAPTURE_REGEX}" '
        map(
          . as $pr
          | select(
              any($agentPrPrefixes[]; (($pr.headRefName // "") | startswith(.)))
              or any(($pr.labels // [])[]?; .name == "agent-handoff")
              or any(($pr.comments // [])[]?; ((.body // "") | test("^## PR (final review blocker|repair worker summary|repair summary|repair update)"; "i")))
            )
          | [
              (
                $pr.headRefName
                | capture($branchIssueRegex)?
                | .id
              ),
              (
                ($pr.body // "")
                | capture("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\s+#(?<id>[0-9]+)\\b")?
                | .id
              )
            ]
          | .[]
          | select(. != null and . != "")
        )
        | unique
      '
)"

gh issue list -R "$REPO_SLUG" --state open --limit 100 --json number,title,createdAt,updatedAt,labels \
  | jq -r --argjson openAgentPrIssueIds "$open_agent_pr_issue_ids" --argjson minAgeMinutes "$MIN_AGE_MINUTES" '
      def label_names: [.labels[]?.name];
      def age_minutes:
        ((now - ((.createdAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))) / 60);
      def has_open_agent_pr:
        ((.number | tostring) as $issueId | ($openAgentPrIssueIds | index($issueId)) != null);
      map(
        . + {
          reason:
            (if any(label_names[]?; . == "agent-running") and (has_open_agent_pr | not) then
              "stale-agent-running"
            elif any(label_names[]?; . == "agent-blocked") then
              "blocked-manual-review"
            else
              ""
            end)
        }
      )
      | map(select(.reason != "" and (age_minutes >= $minAgeMinutes)))
      | sort_by(.createdAt, .number)
      | .[]
      | [
          (.number | tostring),
          .reason,
          .createdAt,
          .updatedAt,
          (label_names | join(",")),
          .title
        ]
      | @tsv
    '
