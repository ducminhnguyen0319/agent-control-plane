# ACP Quick Start Guide

Get ACP running in 5 minutes or less!

## Prerequisites

- **Node.js** >= 18 ([install](https://nodejs.org/))
- **git** ([install](https://git-scm.com/))
- **GitHub CLI** (for GitHub repos): `gh auth login`

## Option A: Interactive Wizard (Recommended)

```bash
# Install ACP
npm install -g agent-control-plane

# Run the wizard - it guides you through everything!
agent-control-plane setup
```

The wizard will:
1. Detect your repo and suggest defaults
2. Help you choose a coding worker (codex, claude, ollama, etc.)
3. Set up everything automatically
4. Start the dashboard at http://127.0.0.1:8765
5. Offer to create starter issues for ACP to work on

**That's it!** Open http://127.0.0.1:8765 in your browser to see ACP in action.

---

## Option B: Manual Setup (2 minutes)

```bash
# 1. Install
npm install -g agent-control-plane

# 2. Initialize a profile
agent-control-plane init \
  --profile-id my-repo \
  --repo-slug owner/repo \
  --forge-provider github \
  --repo-root ~/src/my-repo \
  --coding-worker codex

# 3. Start the runtime
agent-control-plane runtime start --profile-id my-repo

# 4. Start the dashboard
agent-control-plane dashboard start

# 5. Open browser
# Visit: http://127.0.0.1:8765
```

---

## Choose Your Coding Worker

| Worker | Best For | Requirements |
| --- | --- | --- |
| **codex** | Production use | OpenAI API key |
| **claude** | Production use | Anthropic API key |
| **openclaw** | Production use | API key |
| **ollama** | Local/private | Ollama installed locally |
| **pi** | Free tier | OpenRouter API key |
| **opencode** | Research | Charm Crush installed |
| **kilo** | Research | Kilo Code installed |

**New to ACP?** Start with `codex` or `claude` for best results.

---

## Verify Installation

```bash
# Check if ACP is working
agent-control-plane doctor

# Check runtime status
agent-control-plane runtime status --profile-id my-repo

# Check dashboard
curl http://127.0.0.1:8765/health
```

---

## Next Steps

1. **Watch ACP work**: The dashboard shows all activity
2. **Create issues**: Label any GitHub issue with `agent-keep-open` and ACP will work on it
3. **Read the docs**: See [README.md](./README.md) for full documentation
4. **Join discussions**: [GitHub Discussions](https://github.com/ducminhnguyen0319/agent-control-plane/discussions)

---

## Troubleshooting

**Dashboard shows "Reconnecting"?**
→ Make sure the dashboard server is running: `agent-control-plane dashboard status`

**Worker fails to start?**
→ Check backend authentication: ensure API keys are set

**Port 8765 already in use?**
→ Use a different port: `agent-control-plane dashboard start --port 8766`

**Need help?**
→ Check [FAQ](./README.md#faq) or open an issue!

---

Happy coding with ACP! 🚀
