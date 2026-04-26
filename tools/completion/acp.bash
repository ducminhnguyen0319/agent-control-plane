# bash completion for agent-control-plane
# Source this file from your .bashrc or .bash_profile:
#   source /path/to/agent-control-plane/tools/completion/acp.bash

_acp_completion() {
  local cur prev words cword
  _init_completion || return

  # Commands
  local commands="doctor smoke init runtime dashboard sync help"

  # Options for each command
  local doctor_opts="--profile-id --json"
  local smoke_opts="--profile-id --json"
  local init_opts="--profile-id --repo-slug --forge-provider --repo-root --agent-root --worktree-root --coding-worker --gitea-base-url --gitea-token"
  local runtime_opts="start stop status restart --profile-id"
  local dashboard_opts="start stop status --profile-id"
  local sync_opts="--profile-id"

  # Worker types
  local workers="codex claude openclaw ollama pi opencode kilo gemini-cli nanoclaw picoclaw"

  # Forge providers
  local providers="github gitea"

  # If no command yet, complete with commands
  if [[ $cword -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi

  local cmd=${words[1]}

  case "$cmd" in
    doctor)
      COMPREPLY=($(compgen -W "$doctor_opts" -- "$cur"))
      ;;
    smoke)
      COMPREPLY=($(compgen -W "$smoke_opts" -- "$cur"))
      ;;
    init)
      case "$prev" in
        --forge-provider)
          COMPREPLY=($(compgen -W "$providers" -- "$cur"))
          return
          ;;
        --coding-worker)
          COMPREPLY=($(compgen -W "$workers" -- "$cur"))
          return
          ;;
        *)
          COMPREPLY=($(compgen -W "$init_opts" -- "$cur"))
          ;;
      esac
      ;;
    runtime)
      local runtime_cmds="start stop status restart"
      if [[ $cword -eq 2 ]]; then
        COMPREPLY=($(compgen -W "$runtime_cmds" -- "$cur"))
      else
        COMPREPLY=($(compgen -W "$runtime_opts" -- "$cur"))
      fi
      ;;
    dashboard)
      local dashboard_cmds="start stop status"
      if [[ $cword -eq 2 ]]; then
        COMPREPLY=($(compgen -W "$dashboard_cmds" -- "$cur"))
      else
        COMPREPLY=($(compgen -W "$dashboard_opts" -- "$cur"))
      fi
      ;;
    sync)
      COMPREPLY=($(compgen -W "$sync_opts" -- "$cur"))
      ;;
    *)
      COMPREPLY=($(compgen -W "$commands" -- "$cur"))
      ;;
  esac

  # Complete profile IDs from ~/.agent-runtime/control-plane/profiles/
  if [[ "$cur" == --profile-id* || "$prev" == "--profile-id" ]]; then
    local profiles_dir="$HOME/.agent-runtime/control-plane/profiles"
    if [[ -d "$profiles_dir" ]]; then
      local profiles=$(ls -1 "$profiles_dir" 2>/dev/null)
      COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
    fi
  fi
}

complete -F _acp_completion agent-control-plane
complete -F _acp_completion npx  # Also complete for npx agent-control-plane@latest

# vim:ft=bash
