# Contributing to Agent Control Plane (ACP)

Thank you for your interest in contributing to ACP! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Commit Messages](#commit-messages)
- [Release Process](#release-process)

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md) (if available) or the [Contributor Covenant](https://www.contributor-covenant.org/).

## Getting Started

### Prerequisites

- **Node.js** >= 18 (recommended: v20 or v22)
- **bash** (v4+)
- **git**
- **jq** (for JSON parsing)
- **python3** (for dashboard and scripts)
- **tmux** (for background worker sessions)

See [README.md](README.md#prerequisites) for detailed installation instructions.

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/ducminhnguyen0319/agent-control-plane.git
cd agent-control-plane

# Run the setup wizard
bash tools/bin/setup-wizard.sh

# Or manual setup
npx agent-control-plane@latest init \
  --profile-id my-dev \
  --repo-slug owner/repo \
  --forge-provider github \
  --repo-root . \
  --coding-worker codex

# Verify setup
bash tools/bin/setup-verify.sh --profile-id my-dev
```

## Development Setup

### 1. Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/agent-control-plane.git
   cd agent-control-plane
   ```

3. Add upstream remote:
   ```bash
   git remote add upstream https://github.com/ducminhnguyen0319/agent-control-plane.git
   ```

### 2. Install Dependencies

```bash
npm install
```

### 3. Create a Development Profile

```bash
npx agent-control-plane@latest init \
  --profile-id dev \
  --repo-slug yourname/agent-control-plane \
  --repo-root . \
  --agent-root ~/.agent-runtime/projects/acp-dev \
  --worktree-root /tmp/acp-dev-worktrees \
  --coding-worker codex
```

### 4. Start Development Runtime

```bash
npx agent-control-plane@latest runtime start --profile-id dev
npx agent-control-plane@latest dashboard start
```

## Making Changes

### Branch Naming

Use the following prefix conventions:

- `feat/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code refactoring
- `test/` - Test updates
- `chore/` - Maintenance tasks

Examples:
- `feat/scheduler-metrics`
- `fix/ollama-timeout`
- `docs/update-readme`

### Keeping Your Branch Updated

```bash
git fetch upstream
git checkout main
git merge upstream/main
git checkout your-feature-branch
git rebase main
```

## Testing

### Running Tests

```bash
# Run all tests
npm test

# Run specific test
bash tools/tests/test-package-surface.sh

# Run smoke test
npm run smoke

# Run doctor (system checks)
npm run doctor
```

### Test Coverage

We aim for high test coverage. Please add tests for new features:

- **Bash scripts**: Add tests to `tools/tests/`
- **Node.js code**: Add tests to `npm/tests/`
- **Dashboard**: Manual testing via `npm run dashboard`

### Manual Testing Checklist

Before submitting a PR:

- [ ] Run `npm test` and all tests pass
- [ ] Run `npm run doctor` and fix any issues
- [ ] Test the change with a real profile
- [ ] Check cross-platform compatibility (macOS/Linux)
- [ ] Update documentation if needed
- [ ] Add tests for new functionality

## Pull Request Process

### 1. Create a Pull Request

- Fill in the PR template completely
- Link to any related issues
- Add screenshots for UI changes
- Keep PRs focused on a single concern

### 2. PR Checklist

- [ ] Branch is up to date with `main`
- [ ] All tests pass
- [ ] Code follows project style guidelines
- [ ] Documentation updated (if needed)
- [ ] Tests added/updated (if needed)
- [ ] CHANGELOG.md updated (for user-facing changes)

### 3. Review Process

1. A maintainer will review your PR
2. Address any feedback promptly
3. Once approved, the PR will be merged
4. Your changes will be included in the next release

## Coding Standards

### Bash Scripts

- Use `set -euo pipefail` at the top
- Use `local` for local variables
- Quote all variable expansions: `"$var"` not `$var`
- Use `shellcheck` for linting: `shellcheck tools/bin/*.sh`
- Add comments for complex logic

Example:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if command exists
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed" >&2
    return 1
  fi
}
```

### Node.js Code

- Use ES module syntax (`import`/`export`)
- Use `async`/`await` for asynchronous code
- Handle errors with `try`/`catch`
- Add JSDoc comments for functions

Example:
```javascript
import { readFile } from 'fs/promises';

/**
 * Read and parse a JSON file.
 * @param {string} filePath - Path to the JSON file.
 * @returns {Promise<object>} Parsed JSON object.
 */
export async function readJsonFile(filePath) {
  try {
    const content = await readFile(filePath, 'utf-8');
    return JSON.parse(content);
  } catch (error) {
    throw new Error(`Failed to read ${filePath}: ${error.message}`);
  }
}
```

### Documentation

- Use Markdown for documentation
- Keep README.md up to date
- Add JSDoc comments to all public functions
- Update CHANGELOG.md for user-facing changes

## Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation changes
- **style**: Code style changes (formatting, etc.)
- **refactor**: Code refactoring
- **perf**: Performance improvements
- **test**: Test updates
- **chore**: Maintenance tasks

### Examples

```bash
feat(scheduler): add retry backoff for transient failures

- Add exponential backoff with jitter
- Configurable max retries and base delay
- Log retry attempts with attempt number

Fixes #123
```

```bash
fix(ollama): handle context window detection

The ollama adapter now correctly parses model_info
to detect context window size.

Closes #456
```

## Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (x.0.0): Breaking changes
- **MINOR** (0.x.0): New features (backward compatible)
- **PATCH** (0.0.x): Bug fixes (backward compatible)

### Creating a Release

1. Update version in `package.json`
2. Update `CHANGELOG.md`
3. Create a release commit:
   ```bash
   git add package.json CHANGELOG.md
   git commit -m "chore: release v0.7.2"
   ```
4. Create a git tag:
   ```bash
   git tag v0.7.2
   git push origin v0.7.2
   ```
5. GitHub Actions will automatically publish to npm

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/ducminhnguyen0319/agent-control-plane/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ducminhnguyen0319/agent-control-plane/discussions)
- **Documentation**: [README.md](README.md)

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see [LICENSE](LICENSE) file).
