# fish completion for agent-control-plane
# Save to ~/.config/fish/completions/acp.fish or source directly:
#   source /path/to/agent-control-plane/tools/completion/acp.fish

# Disable file completion by default
complete -c agent-control-plane -f

# Helper: list profile IDs from ~/.agent-runtime/control-plane/profiles/
function __acp_profiles
    set -l profiles_dir "$HOME/.agent-runtime/control-plane/profiles"
    if test -d $profiles_dir
        ls -1 $profiles_dir 2>/dev/null
    end
end

# Helper: check if a subcommand is already given
function __acp_no_subcommand
    for word in (commandline -opc)
        switch $word
            case doctor smoke init runtime dashboard sync help
                return 1
        end
    end
    return 0
end

function __acp_using_subcommand
    set -l cmd $argv[1]
    for word in (commandline -opc)
        if test $word = $cmd
            return 0
        end
    end
    return 1
end

# Top-level commands
complete -c agent-control-plane -n __acp_no_subcommand -a doctor    -d 'Check ACP installation health'
complete -c agent-control-plane -n __acp_no_subcommand -a smoke     -d 'Run smoke tests'
complete -c agent-control-plane -n __acp_no_subcommand -a init      -d 'Initialize a new profile'
complete -c agent-control-plane -n __acp_no_subcommand -a runtime   -d 'Manage runtime (start/stop/status/restart)'
complete -c agent-control-plane -n __acp_no_subcommand -a dashboard -d 'Manage dashboard (start/stop/status)'
complete -c agent-control-plane -n __acp_no_subcommand -a sync      -d 'Sync runtime to latest'
complete -c agent-control-plane -n __acp_no_subcommand -a help      -d 'Show help'

# doctor options
complete -c agent-control-plane -n '__acp_using_subcommand doctor' -l profile-id -d 'Profile ID' -a '(__acp_profiles)'
complete -c agent-control-plane -n '__acp_using_subcommand doctor' -l json       -d 'Output JSON'

# smoke options
complete -c agent-control-plane -n '__acp_using_subcommand smoke' -l profile-id -d 'Profile ID' -a '(__acp_profiles)'
complete -c agent-control-plane -n '__acp_using_subcommand smoke' -l json       -d 'Output JSON'

# init options
complete -c agent-control-plane -n '__acp_using_subcommand init' -l profile-id      -d 'Profile ID'
complete -c agent-control-plane -n '__acp_using_subcommand init' -l repo-slug       -d 'Repository slug (owner/repo)'
complete -c agent-control-plane -n '__acp_using_subcommand init' -l forge-provider  -d 'Forge provider' -a 'github gitea'
complete -c agent-control-plane -n '__acp_using_subcommand init' -l repo-root       -d 'Repository root path' -F
complete -c agent-control-plane -n '__acp_using_subcommand init' -l agent-root      -d 'Agent root path' -F
complete -c agent-control-plane -n '__acp_using_subcommand init' -l worktree-root   -d 'Worktree root path' -F
complete -c agent-control-plane -n '__acp_using_subcommand init' -l coding-worker   -d 'Coding worker' -a 'codex claude openclaw ollama pi opencode kilo gemini-cli nanoclaw picoclaw'
complete -c agent-control-plane -n '__acp_using_subcommand init' -l gitea-base-url  -d 'Gitea base URL'
complete -c agent-control-plane -n '__acp_using_subcommand init' -l gitea-token     -d 'Gitea token'

# runtime subcommands and options
complete -c agent-control-plane -n '__acp_using_subcommand runtime' -a start   -d 'Start the runtime'
complete -c agent-control-plane -n '__acp_using_subcommand runtime' -a stop    -d 'Stop the runtime'
complete -c agent-control-plane -n '__acp_using_subcommand runtime' -a status  -d 'Show runtime status'
complete -c agent-control-plane -n '__acp_using_subcommand runtime' -a restart -d 'Restart the runtime'
complete -c agent-control-plane -n '__acp_using_subcommand runtime' -l profile-id -d 'Profile ID' -a '(__acp_profiles)'

# dashboard subcommands and options
complete -c agent-control-plane -n '__acp_using_subcommand dashboard' -a start  -d 'Start the dashboard'
complete -c agent-control-plane -n '__acp_using_subcommand dashboard' -a stop   -d 'Stop the dashboard'
complete -c agent-control-plane -n '__acp_using_subcommand dashboard' -a status -d 'Show dashboard status'
complete -c agent-control-plane -n '__acp_using_subcommand dashboard' -l profile-id -d 'Profile ID' -a '(__acp_profiles)'

# sync options
complete -c agent-control-plane -n '__acp_using_subcommand sync' -l profile-id -d 'Profile ID' -a '(__acp_profiles)'

# vim:ft=fish
