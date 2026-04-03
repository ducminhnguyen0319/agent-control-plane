#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");
const util = require("util");
const { spawnSync } = require("child_process");

const packageRoot = path.resolve(__dirname, "..", "..");
const packageJson = require(path.join(packageRoot, "package.json"));
const skillName = "agent-control-plane";
let setupJsonOutputEnabled = false;

function printHelp() {
  console.log(`agent-control-plane ${packageJson.version}

Usage:
  agent-control-plane <command> [args...]

Commands:
  help                 Show this help
  version              Print package version
  setup                Guided setup flow for one repo profile
  onboard              Alias for setup
  sync                 Publish the packaged runtime into ~/.agent-runtime
  install              Alias for sync
  init                 Scaffold and adopt a project profile
  doctor               Inspect runtime/source installation state
  profile-smoke        Validate installed profiles
  dashboard            Start the dashboard server
  launchd-install      Install a per-project LaunchAgent (macOS)
  launchd-uninstall    Remove a per-project LaunchAgent (macOS)
  runtime              Forward to tools/bin/project-runtimectl.sh
  remove               Remove one installed profile and runtime state
  smoke                Run the packaged smoke suite
`);
}

function printSetupHelp() {
  console.log(`agent-control-plane setup

Usage:
  agent-control-plane setup [options]

Guided install/bootstrap flow for one repo profile. It can detect the current
repo, suggest sane runtime paths, sync ACP into ~/.agent-runtime, scaffold one
profile, run doctor checks, and optionally start the runtime.

Options:
  --profile-id <id>            Profile id to create or refresh
  --repo-slug <owner/repo>     GitHub repo slug
  --repo-root <path>           Local checkout to manage (defaults to current git root)
  --agent-root <path>          ACP-managed runtime root for this profile
  --agent-repo-root <path>     Clean ACP-managed anchor repo root
  --worktree-root <path>       Parent root for ACP worktrees
  --retained-repo-root <path>  Manual checkout root to keep linked in the profile
  --vscode-workspace-file <path>
                               Workspace file path ACP should generate/use
  --coding-worker <backend>    One of: codex, claude, openclaw
  --force                      Overwrite an existing profile
  --skip-anchor-sync           Skip profile-adopt anchor repo sync
  --skip-workspace-sync        Skip profile-adopt workspace sync
  --allow-missing-repo         Allow setup even when the source repo is incomplete
  --install-missing-deps       Install missing core dependencies automatically when supported
  --no-install-missing-deps    Skip dependency installation prompts and auto install
  --install-missing-backend    Install the selected worker backend automatically when ACP knows how
  --no-install-missing-backend Skip worker backend installation prompts and auto install
  --gh-auth-login              Run \`gh auth login\` automatically when GitHub auth is not ready
  --no-gh-auth-login           Skip the GitHub auth prompt during setup
  --dry-run                    Render the setup plan without making changes
  --plan                       Alias for --dry-run
  --json                       Emit one JSON result object and send progress logs to stderr
  --start-runtime              Start the runtime after setup
  --no-start-runtime           Do not start the runtime after setup
  --install-launchd            Install macOS autostart after a successful runtime start
  --no-install-launchd         Do not install macOS autostart
  --yes                        Accept detected defaults without prompting
  --non-interactive            Same as --yes
  --help                       Show this help
`);
}

function copyTree(sourceDir, targetDir) {
  if (!fs.existsSync(sourceDir)) {
    return;
  }

  fs.cpSync(sourceDir, targetDir, {
    recursive: true,
    filter: (sourcePath) => {
      const base = path.basename(sourcePath);
      if (base === ".git" || base === "node_modules" || base === ".DS_Store") {
        return false;
      }
      if (base === "__pycache__") {
        return false;
      }
      if (base.endsWith(".bak") || base.endsWith(".bak2") || base.endsWith(".bak3")) {
        return false;
      }
      return true;
    }
  });
}

function stageSharedHome() {
  const stageRoot = fs.mkdtempSync(path.join(os.tmpdir(), "agent-control-plane-"));
  const sharedHome = path.join(stageRoot, "shared-home");
  const stagedSkillRoot = path.join(sharedHome, "skills", "openclaw", skillName);

  fs.mkdirSync(path.dirname(stagedSkillRoot), { recursive: true });
  copyTree(packageRoot, stagedSkillRoot);
  copyTree(path.join(packageRoot, "tools"), path.join(sharedHome, "tools"));

  return {
    stageRoot: fs.realpathSync.native(stageRoot),
    sharedHome: fs.realpathSync.native(sharedHome),
    stagedSkillRoot: fs.realpathSync.native(stagedSkillRoot)
  };
}

function resolvePlatformHome(env = process.env) {
  const homeDir = env.HOME || os.homedir();
  return env.AGENT_PLATFORM_HOME || path.join(homeDir, ".agent-runtime");
}

function createExecutionContext(stage) {
  const homeDir = process.env.HOME || os.homedir();
  const platformHome = resolvePlatformHome(process.env);
  const runtimeHome = path.join(platformHome, "runtime-home");
  const profileRegistryRoot = path.join(platformHome, "control-plane", "profiles");
  const env = {
    ...process.env,
    SHARED_AGENT_HOME: stage.sharedHome,
    AGENT_CONTROL_PLANE_ROOT: stage.stagedSkillRoot,
    ACP_ROOT: stage.stagedSkillRoot,
    AGENT_FLOW_SOURCE_ROOT: stage.stagedSkillRoot,
    ACP_PROJECT_INIT_SOURCE_HOME: stage.sharedHome,
    ACP_PROJECT_INIT_RUNTIME_HOME: runtimeHome,
    ACP_PROJECT_RUNTIME_SOURCE_HOME: stage.sharedHome,
    ACP_DASHBOARD_SOURCE_HOME: stage.sharedHome,
    ACP_PROFILE_REGISTRY_ROOT: profileRegistryRoot,
    ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT: profileRegistryRoot,
    ACP_DASHBOARD_PROFILE_REGISTRY_ROOT: profileRegistryRoot,
    HOME: homeDir
  };

  return {
    ...stage,
    env,
    homeDir,
    platformHome,
    runtimeHome,
    profileRegistryRoot
  };
}

function runScriptWithContext(context, scriptRelativePath, forwardedArgs, options = {}) {
  const scriptPath = options.scriptPath || path.join(packageRoot, scriptRelativePath);
  const stdio = options.stdio || "inherit";
  const result = spawnSync("bash", [scriptPath, ...forwardedArgs], {
    stdio,
    encoding: stdio === "inherit" ? undefined : "utf8",
    env: options.env || context.env,
    cwd: options.cwd || process.cwd()
  });

  if (typeof result.status === "number") {
    return result;
  }

  return {
    ...result,
    status: result.error ? 1 : 0
  };
}

function resolvePersistentSourceHome(context) {
  if (process.env.ACP_PROJECT_RUNTIME_SOURCE_HOME) {
    return process.env.ACP_PROJECT_RUNTIME_SOURCE_HOME;
  }
  if (fs.existsSync(path.join(packageRoot, ".git"))) {
    return packageRoot;
  }
  return context.runtimeHome;
}

function runtimeSkillRoot(context) {
  return path.join(context.runtimeHome, "skills", "openclaw", skillName);
}

function createRuntimeExecutionContext(context) {
  const stableSkillRoot = runtimeSkillRoot(context);
  const persistentSourceHome = resolvePersistentSourceHome(context);
  const runtimeScriptEnv = {
    ACP_PROJECT_RUNTIME_SYNC_SCRIPT:
      context.env.ACP_PROJECT_RUNTIME_SYNC_SCRIPT || path.join(stableSkillRoot, "tools", "bin", "sync-shared-agent-home.sh"),
    ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT:
      context.env.ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT || path.join(stableSkillRoot, "tools", "bin", "ensure-runtime-sync.sh"),
    ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT:
      context.env.ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT || path.join(stableSkillRoot, "tools", "bin", "project-launchd-bootstrap.sh"),
    ACP_PROJECT_RUNTIME_SUPERVISOR_SCRIPT:
      context.env.ACP_PROJECT_RUNTIME_SUPERVISOR_SCRIPT || path.join(stableSkillRoot, "tools", "bin", "project-runtime-supervisor.sh"),
    ACP_PROJECT_RUNTIME_KICK_SCRIPT:
      context.env.ACP_PROJECT_RUNTIME_KICK_SCRIPT || path.join(stableSkillRoot, "tools", "bin", "kick-scheduler.sh")
  };
  return {
    ...context,
    stableSkillRoot,
    persistentSourceHome,
    env: {
      ...context.env,
      SHARED_AGENT_HOME: context.runtimeHome,
      AGENT_CONTROL_PLANE_ROOT: stableSkillRoot,
      ACP_ROOT: stableSkillRoot,
      AGENT_FLOW_SOURCE_ROOT: stableSkillRoot,
      ACP_PROJECT_INIT_SOURCE_HOME: persistentSourceHome,
      ACP_PROJECT_RUNTIME_SOURCE_HOME: persistentSourceHome,
      ACP_DASHBOARD_SOURCE_HOME: persistentSourceHome,
      ...runtimeScriptEnv
    }
  };
}

function syncRuntimeHome(context, options = {}) {
  const result = runScriptWithContext(context, "tools/bin/sync-shared-agent-home.sh", [], {
    stdio: options.stdio || "inherit"
  });
  if (result.status !== 0) {
    throw new Error("failed to sync runtime home before command execution");
  }
}

function runCommand(scriptRelativePath, forwardedArgs) {
  const stage = stageSharedHome();
  const context = createExecutionContext(stage);

  try {
    if (scriptRelativePath !== "tools/bin/sync-shared-agent-home.sh") {
      syncRuntimeHome(context, { stdio: "inherit" });
      const runtimeContext = createRuntimeExecutionContext(context);
      const runtimeScriptPath = path.join(runtimeContext.stableSkillRoot, scriptRelativePath);
      const result = runScriptWithContext(runtimeContext, scriptRelativePath, forwardedArgs, {
        stdio: "inherit",
        scriptPath: runtimeScriptPath
      });
      return result.status;
    }

    const result = runScriptWithContext(context, scriptRelativePath, forwardedArgs, { stdio: "inherit" });
    return result.status;
  } finally {
    fs.rmSync(stage.stageRoot, { recursive: true, force: true });
  }
}

function runCapture(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    env: options.env || process.env,
    cwd: options.cwd || process.cwd(),
    timeout: options.timeoutMs || 0
  });
  return {
    status: typeof result.status === "number" ? result.status : (result.error ? 1 : 0),
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    error: result.error || null
  };
}

function commandExists(command) {
  return runCapture("bash", ["-lc", `command -v ${JSON.stringify(command)} >/dev/null 2>&1`]).status === 0;
}

function detectRepoRoot(startDir) {
  const probe = runCapture("git", ["rev-parse", "--show-toplevel"], { cwd: startDir });
  if (probe.status !== 0) {
    return "";
  }
  return probe.stdout.trim();
}

function parseGithubRepoSlug(remoteUrl) {
  const trimmed = String(remoteUrl || "").trim();
  const patterns = [
    /^git@github\.com:([^/]+\/[^/]+?)(?:\.git)?$/,
    /^https:\/\/github\.com\/([^/]+\/[^/]+?)(?:\.git)?$/,
    /^ssh:\/\/git@github\.com\/([^/]+\/[^/]+?)(?:\.git)?$/
  ];

  for (const pattern of patterns) {
    const match = trimmed.match(pattern);
    if (match) {
      return match[1];
    }
  }

  return "";
}

function detectRepoSlug(repoRoot) {
  if (!repoRoot) {
    return "";
  }
  const remote = runCapture("git", ["remote", "get-url", "origin"], { cwd: repoRoot });
  if (remote.status !== 0) {
    return "";
  }
  return parseGithubRepoSlug(remote.stdout.trim());
}

function sanitizeProfileId(value) {
  const lowered = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (!lowered) {
    return "repo";
  }
  if (/^[a-z0-9]/.test(lowered)) {
    return lowered;
  }
  return `repo-${lowered}`;
}

function detectPreferredWorker() {
  if (commandExists("codex")) {
    return "codex";
  }
  if (commandExists("claude")) {
    return "claude";
  }
  if (commandExists("openclaw")) {
    return "openclaw";
  }
  return "openclaw";
}

function parseKvOutput(text) {
  const records = {};
  for (const rawLine of String(text || "").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || !line.includes("=")) {
      continue;
    }
    const idx = line.indexOf("=");
    const key = line.slice(0, idx);
    const value = line.slice(idx + 1);
    records[key] = value;
  }
  return records;
}

function printFailureDetails(result) {
  const stdoutTarget = setupJsonOutputEnabled ? process.stderr : process.stdout;
  const stderrTarget = process.stderr;
  if (result.stdout) {
    stdoutTarget.write(result.stdout);
    if (!result.stdout.endsWith("\n")) {
      stdoutTarget.write("\n");
    }
  }
  if (result.stderr) {
    stderrTarget.write(result.stderr);
    if (!result.stderr.endsWith("\n")) {
      stderrTarget.write("\n");
    }
  }
}

function parseSetupArgs(args) {
  const options = {
    profileId: "",
    repoSlug: "",
    repoRoot: "",
    agentRoot: "",
    agentRepoRoot: "",
    worktreeRoot: "",
    retainedRepoRoot: "",
    vscodeWorkspaceFile: "",
    codingWorker: "",
    sourceRepoRoot: "",
    force: false,
    skipAnchorSync: false,
    skipWorkspaceSync: false,
    allowMissingRepo: false,
    installMissingDeps: null,
    installMissingBackend: null,
    ghAuthLogin: null,
    dryRun: false,
    json: false,
    startRuntime: null,
    installLaunchd: null,
    interactive: process.stdin.isTTY && process.stdout.isTTY,
    help: false
  };

  for (let index = 0; index < args.length; index += 1) {
    const current = args[index];
    switch (current) {
      case "--profile-id":
        options.profileId = args[++index] || "";
        break;
      case "--repo-slug":
        options.repoSlug = args[++index] || "";
        break;
      case "--repo-root":
        options.repoRoot = args[++index] || "";
        break;
      case "--agent-root":
        options.agentRoot = args[++index] || "";
        break;
      case "--agent-repo-root":
        options.agentRepoRoot = args[++index] || "";
        break;
      case "--worktree-root":
        options.worktreeRoot = args[++index] || "";
        break;
      case "--retained-repo-root":
        options.retainedRepoRoot = args[++index] || "";
        break;
      case "--vscode-workspace-file":
        options.vscodeWorkspaceFile = args[++index] || "";
        break;
      case "--coding-worker":
        options.codingWorker = args[++index] || "";
        break;
      case "--source-repo-root":
        options.sourceRepoRoot = args[++index] || "";
        break;
      case "--force":
        options.force = true;
        break;
      case "--skip-anchor-sync":
        options.skipAnchorSync = true;
        break;
      case "--skip-workspace-sync":
        options.skipWorkspaceSync = true;
        break;
      case "--allow-missing-repo":
        options.allowMissingRepo = true;
        break;
      case "--install-missing-deps":
        options.installMissingDeps = true;
        break;
      case "--no-install-missing-deps":
        options.installMissingDeps = false;
        break;
      case "--install-missing-backend":
        options.installMissingBackend = true;
        break;
      case "--no-install-missing-backend":
        options.installMissingBackend = false;
        break;
      case "--gh-auth-login":
        options.ghAuthLogin = true;
        break;
      case "--no-gh-auth-login":
        options.ghAuthLogin = false;
        break;
      case "--dry-run":
      case "--plan":
        options.dryRun = true;
        break;
      case "--json":
        options.json = true;
        options.interactive = false;
        break;
      case "--start-runtime":
        options.startRuntime = true;
        break;
      case "--no-start-runtime":
        options.startRuntime = false;
        break;
      case "--install-launchd":
        options.installLaunchd = true;
        break;
      case "--no-install-launchd":
        options.installLaunchd = false;
        break;
      case "--yes":
      case "--non-interactive":
        options.interactive = false;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Unknown argument for setup: ${current}`);
    }
  }

  return options;
}

function createPromptInterface() {
  return readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
}

function printWizardBanner() {
  console.log("============================================================");
  console.log("  Agent Control Plane — Setup Wizard");
  console.log("============================================================");
  console.log("");
  console.log("This wizard will guide you through setting up one repo profile.");
  console.log("Press Enter at any prompt to accept the value shown in [brackets].");
  console.log("");
}

function printWizardStep(step, total, title) {
  console.log(`\n[${step}/${total}] ${title}`);
}

function question(rl, prompt) {
  return new Promise((resolve) => rl.question(prompt, resolve));
}

async function promptText(rl, label, defaultValue) {
  const suffix = defaultValue ? ` [${defaultValue}]` : "";
  const answer = (await question(rl, `${label}${suffix}: `)).trim();
  return answer || defaultValue;
}

async function promptYesNo(rl, label, defaultValue) {
  const suffix = defaultValue ? " [Y/n]" : " [y/N]";
  const answer = (await question(rl, `${label}${suffix}: `)).trim().toLowerCase();
  if (!answer) {
    return defaultValue;
  }
  if (answer === "y" || answer === "yes") {
    return true;
  }
  if (answer === "n" || answer === "no") {
    return false;
  }
  return defaultValue;
}

function buildSetupPaths(platformHome, repoRoot, profileId, overrides) {
  const agentRoot = path.resolve(overrides.agentRoot || path.join(platformHome, "projects", profileId));
  const repoRootResolved = path.resolve(repoRoot);
  return {
    repoRoot: repoRootResolved,
    agentRoot,
    agentRepoRoot: path.resolve(overrides.agentRepoRoot || path.join(agentRoot, "repo")),
    worktreeRoot: path.resolve(overrides.worktreeRoot || path.join(agentRoot, "worktrees")),
    retainedRepoRoot: path.resolve(overrides.retainedRepoRoot || repoRootResolved),
    vscodeWorkspaceFile: path.resolve(overrides.vscodeWorkspaceFile || path.join(agentRoot, `${profileId}-agents.code-workspace`)),
    sourceRepoRoot: path.resolve(overrides.sourceRepoRoot || repoRootResolved)
  };
}

function collectPrereqStatus(codingWorker) {
  const requiredTools = ["bash", "git", "gh", "jq", "python3", "tmux"];
  const missingRequired = requiredTools.filter((tool) => !commandExists(tool));
  const workerCommand = codingWorker;
  const workerAvailable = commandExists(workerCommand);
  const ghAuthResult = commandExists("gh") ? runCapture("gh", ["auth", "status"]) : { status: 1, stdout: "", stderr: "" };

  return {
    missingRequired,
    coreToolsOk: missingRequired.length === 0,
    workerCommand,
    workerAvailable,
    ghAuthOk: ghAuthResult.status === 0,
    ghAuthOutput: `${ghAuthResult.stdout}${ghAuthResult.stderr}`.trim()
  };
}

function detectPackageManager() {
  if (commandExists("brew")) {
    return { name: "brew" };
  }
  if (commandExists("apt-get")) {
    return { name: "apt-get" };
  }
  if (commandExists("dnf")) {
    return { name: "dnf" };
  }
  if (commandExists("yum")) {
    return { name: "yum" };
  }
  if (commandExists("pacman")) {
    return { name: "pacman" };
  }
  return null;
}

function dependencyPackageMap(managerName) {
  switch (managerName) {
    case "brew":
      return {
        bash: "bash",
        git: "git",
        gh: "gh",
        jq: "jq",
        python3: "python",
        tmux: "tmux"
      };
    case "apt-get":
      return {
        bash: "bash",
        git: "git",
        gh: "gh",
        jq: "jq",
        python3: "python3",
        tmux: "tmux"
      };
    case "dnf":
    case "yum":
      return {
        bash: "bash",
        git: "git",
        gh: "gh",
        jq: "jq",
        python3: "python3",
        tmux: "tmux"
      };
    case "pacman":
      return {
        bash: "bash",
        git: "git",
        gh: "github-cli",
        jq: "jq",
        python3: "python",
        tmux: "tmux"
      };
    default:
      return {};
  }
}

function sudoPrefix() {
  if (typeof process.getuid === "function" && process.getuid() === 0) {
    return [];
  }
  return commandExists("sudo") ? ["sudo"] : [];
}

function buildDependencyInstallPlan(missingTools) {
  const manager = detectPackageManager();
  if (!manager) {
    return null;
  }

  const packageMap = dependencyPackageMap(manager.name);
  const packages = [...new Set(
    missingTools
      .map((tool) => packageMap[tool])
      .filter(Boolean)
  )];

  if (packages.length === 0) {
    return null;
  }

  const prefix = sudoPrefix();
  const commands = [];
  switch (manager.name) {
    case "brew":
      commands.push(["brew", "install", ...packages]);
      break;
    case "apt-get":
      commands.push([...prefix, "apt-get", "update"]);
      commands.push([...prefix, "apt-get", "install", "-y", ...packages]);
      break;
    case "dnf":
      commands.push([...prefix, "dnf", "install", "-y", ...packages]);
      break;
    case "yum":
      commands.push([...prefix, "yum", "install", "-y", ...packages]);
      break;
    case "pacman":
      commands.push([...prefix, "pacman", "-Sy", "--noconfirm", ...packages]);
      break;
    default:
      return null;
  }

  return {
    manager: manager.name,
    packages,
    commands
  };
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function formatCommand(args) {
  return args.map(shellQuote).join(" ");
}

function runInteractiveCommand(command, args) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    env: process.env
  });
  return typeof result.status === "number" ? result.status : (result.error ? 1 : 0);
}

async function maybeInstallMissingDependencies(options, prereq) {
  if (prereq.coreToolsOk) {
    return {
      status: "not-needed",
      reason: "",
      installer: "",
      commands: []
    };
  }

  const plan = buildDependencyInstallPlan(prereq.missingRequired);
  if (!plan) {
    console.log("\nACP found missing core dependencies but cannot install them automatically on this machine.");
    console.log(`- missing tools: ${prereq.missingRequired.join(", ")}`);
    console.log("- supported auto-install package managers today: brew, apt-get, dnf, yum, pacman");
    return {
      status: "unavailable",
      reason: "no-supported-package-manager",
      installer: "",
      commands: []
    };
  }

  if (options.installMissingDeps === false) {
    console.log("\nSkipping dependency installation because the setup flags disabled it.");
    return {
      status: "skipped",
      reason: "disabled",
      installer: plan.manager,
      commands: plan.commands
    };
  }

  let shouldInstall = options.installMissingDeps === true;
  if (options.installMissingDeps === null && options.interactive) {
    console.log("\nACP can install the missing core dependencies for you.");
    console.log(`- package manager: ${plan.manager}`);
    console.log(`- packages: ${plan.packages.join(", ")}`);
    console.log(`- command preview: ${plan.commands.map(formatCommand).join(" && ")}`);
    const rl = createPromptInterface();
    try {
      shouldInstall = await promptYesNo(rl, "Install missing core dependencies now", true);
    } finally {
      rl.close();
    }
  }

  if (!shouldInstall) {
    console.log("\nDependency installation skipped.");
    return {
      status: "skipped",
      reason: "not-confirmed",
      installer: plan.manager,
      commands: plan.commands
    };
  }

  console.log("\nInstalling missing core dependencies...");
  for (const commandArgs of plan.commands) {
    const [command, ...rest] = commandArgs;
    console.log(`> ${formatCommand(commandArgs)}`);
    const status = runInteractiveCommand(command, rest);
    if (status !== 0) {
      return {
        status: "failed",
        reason: `command-failed:${command}`,
        installer: plan.manager,
        commands: plan.commands
      };
    }
  }

  return {
    status: "ok",
    reason: "",
    installer: plan.manager,
    commands: plan.commands
  };
}

async function maybeRunGithubAuthLogin(options, prereq) {
  if (prereq.ghAuthOk) {
    return { status: "not-needed", reason: "" };
  }
  if (!commandExists("gh")) {
    console.log("\nGitHub authentication cannot run yet because `gh` is not installed.");
    return { status: "skipped", reason: "gh-missing" };
  }
  if (options.ghAuthLogin === false) {
    console.log("\nSkipping `gh auth login` because the setup flags disabled it.");
    return { status: "skipped", reason: "disabled" };
  }

  let shouldRun = options.ghAuthLogin === true;
  if (options.ghAuthLogin === null && options.interactive) {
    console.log("\nGitHub CLI is not authenticated for this OS user.");
    const rl = createPromptInterface();
    try {
      shouldRun = await promptYesNo(rl, "Run `gh auth login` now", true);
    } finally {
      rl.close();
    }
  }

  if (!shouldRun) {
    console.log("\nGitHub authentication skipped.");
    return { status: "skipped", reason: "not-confirmed" };
  }

  console.log("\nLaunching GitHub authentication...");
  const status = runInteractiveCommand("gh", ["auth", "login"]);
  if (status !== 0) {
    return { status: "failed", reason: "gh-auth-login-failed" };
  }
  return { status: "ok", reason: "" };
}

function backendReadinessHint(workerCommand) {
  switch (workerCommand) {
    case "codex":
      return "Make sure Codex is installed and authenticated for this OS user before you start background runs.";
    case "claude":
      return "Make sure Claude Code is installed and authenticated for this OS user before you start background runs.";
    case "openclaw":
      return "Make sure OpenClaw is installed and provider credentials are ready before you start background runs.";
    default:
      return "Make sure the selected worker backend is installed and authenticated before you start background runs.";
  }
}

function backendSetupGuide(workerCommand) {
  switch (workerCommand) {
    case "codex":
      return {
        title: "Codex",
        docsUrl: "https://platform.openai.com/docs/codex",
        installExamples: [
          "npm install -g @openai/codex"
        ],
        authExamples: [
          "codex login"
        ],
        verifyExamples: [
          "codex --version",
          "codex login status"
        ],
        note: "ACP can install Codex through npm when npm is available. Authentication and account selection still stay with your local Codex setup."
      };
    case "claude":
      return {
        title: "Claude Code",
        docsUrl: "https://docs.anthropic.com/en/docs/claude-code/setup",
        installExamples: [
          "npm install -g @anthropic-ai/claude-code"
        ],
        authExamples: [
          "claude auth login"
        ],
        verifyExamples: [
          "claude --version",
          "claude doctor"
        ],
        note: "ACP uses the npm install path when available. Anthropic also documents a native installer if you prefer not to use npm."
      };
    case "openclaw":
      return {
        title: "OpenClaw",
        docsUrl: "https://docs.openclaw.ai/start/getting-started",
        installExamples: [
          "npm install -g openclaw@latest"
        ],
        authExamples: [
          "openclaw setup --wizard",
          "openclaw onboard --install-daemon"
        ],
        verifyExamples: [
          "openclaw doctor",
          "openclaw status"
        ],
        note: "ACP uses the npm install path when npm is available. OpenClaw also documents a dedicated install script and onboarding flow."
      };
    default:
      return {
        title: workerCommand,
        docsUrl: "",
        installExamples: [],
        authExamples: [],
        verifyExamples: [],
        note: "Install and authenticate the selected worker backend before you ask ACP to start background runs."
      };
  }
}

function buildWorkerBackendInstallPlan(workerCommand) {
  if (!commandExists("npm")) {
    return null;
  }

  switch (workerCommand) {
    case "codex":
      return {
        installer: "npm",
        commands: [["npm", "install", "-g", "@openai/codex"]]
      };
    case "claude":
      return {
        installer: "npm",
        commands: [["npm", "install", "-g", "@anthropic-ai/claude-code"]]
      };
    case "openclaw":
      return {
        installer: "npm",
        commands: [["npm", "install", "-g", "openclaw@latest"]]
      };
    default:
      return null;
  }
}

function detectUrlOpener() {
  if (commandExists("open")) {
    return "open";
  }
  if (commandExists("xdg-open")) {
    return "xdg-open";
  }
  return "";
}

function printWorkerSetupGuide(guide) {
  console.log(`\n${guide.title} backend setup`);
  if (guide.installExamples.length > 0) {
    console.log("- install");
    for (const example of guide.installExamples) {
      console.log(`  ${example}`);
    }
  }
  if (guide.authExamples.length > 0) {
    console.log("- authenticate");
    for (const example of guide.authExamples) {
      console.log(`  ${example}`);
    }
  }
  if (guide.verifyExamples.length > 0) {
    console.log("- verify");
    for (const example of guide.verifyExamples) {
      console.log(`  ${example}`);
    }
  }
  if (guide.docsUrl) {
    console.log(`- docs: ${guide.docsUrl}`);
  }
  if (guide.note) {
    console.log(`- note: ${guide.note}`);
  }
}

async function maybeShowWorkerSetupGuide(options, prereq) {
  const guide = backendSetupGuide(prereq.workerCommand);
  if (prereq.workerAvailable) {
    return {
      status: "not-needed",
      reason: "",
      installStatus: "not-needed",
      installReason: "",
      installer: "",
      commands: [],
      docsOpened: "not-needed",
      guide
    };
  }

  printWorkerSetupGuide(guide);

  const installPlan = buildWorkerBackendInstallPlan(prereq.workerCommand);
  if (!installPlan) {
    console.log("\nACP does not know a safe automated install command for this worker on the current machine.");
  }

  if (options.installMissingBackend === false) {
    return {
      status: "shown",
      reason: "backend-missing",
      installStatus: "skipped",
      installReason: "disabled",
      installer: installPlan ? installPlan.installer : "",
      commands: installPlan ? installPlan.commands : [],
      docsOpened: installPlan ? "skipped" : "unsupported",
      guide
    };
  }

  let shouldInstall = options.installMissingBackend === true;
  if (!shouldInstall && installPlan && options.installMissingBackend === null && options.interactive) {
    console.log("\nACP can try to install the selected worker backend for you.");
    console.log(`- installer: ${installPlan.installer}`);
    console.log(`- command preview: ${installPlan.commands.map(formatCommand).join(" && ")}`);
    const rl = createPromptInterface();
    try {
      shouldInstall = await promptYesNo(rl, `Install ${guide.title} now`, true);
    } finally {
      rl.close();
    }
  }

  let installStatus = "unavailable";
  let installReason = installPlan ? "" : "no-supported-installer";
  if (installPlan && shouldInstall) {
    console.log(`\nInstalling ${guide.title}...`);
    installStatus = "ok";
    for (const commandArgs of installPlan.commands) {
      const [command, ...rest] = commandArgs;
      console.log(`> ${formatCommand(commandArgs)}`);
      const status = runInteractiveCommand(command, rest);
      if (status !== 0) {
        installStatus = "failed";
        installReason = `command-failed:${command}`;
        break;
      }
    }
  } else if (installPlan) {
    installStatus = "skipped";
    installReason = options.installMissingBackend === null ? "not-confirmed" : "disabled";
  }

  const refreshedPrereq = collectPrereqStatus(prereq.workerCommand);
  if (refreshedPrereq.workerAvailable) {
    return {
      status: "shown",
      reason: "backend-missing",
      installStatus,
      installReason,
      installer: installPlan ? installPlan.installer : "",
      commands: installPlan ? installPlan.commands : [],
      docsOpened: "not-needed",
      guide
    };
  }

  if (!guide.docsUrl) {
    return {
      status: "shown",
      reason: "backend-missing",
      installStatus,
      installReason,
      installer: installPlan ? installPlan.installer : "",
      commands: installPlan ? installPlan.commands : [],
      docsOpened: "unavailable",
      guide
    };
  }

  const opener = detectUrlOpener();
  if (!opener) {
    return {
      status: "shown",
      reason: "backend-missing",
      installStatus,
      installReason,
      installer: installPlan ? installPlan.installer : "",
      commands: installPlan ? installPlan.commands : [],
      docsOpened: "unsupported",
      guide
    };
  }

  if (!options.interactive) {
    return {
      status: "shown",
      reason: "backend-missing",
      installStatus,
      installReason,
      installer: installPlan ? installPlan.installer : "",
      commands: installPlan ? installPlan.commands : [],
      docsOpened: "skipped",
      guide
    };
  }

  const rl = createPromptInterface();
  let shouldOpen = false;
  try {
    shouldOpen = await promptYesNo(rl, `Open ${guide.title} setup docs in your browser now`, false);
  } finally {
    rl.close();
  }

  if (!shouldOpen) {
    return {
      status: "shown",
      reason: "backend-missing",
      installStatus,
      installReason,
      installer: installPlan ? installPlan.installer : "",
      commands: installPlan ? installPlan.commands : [],
      docsOpened: "skipped",
      guide
    };
  }

  const status = runInteractiveCommand(opener, [guide.docsUrl]);
  return {
    status: "shown",
    reason: "backend-missing",
    installStatus,
    installReason,
    installer: installPlan ? installPlan.installer : "",
    commands: installPlan ? installPlan.commands : [],
    docsOpened: status === 0 ? "yes" : "failed",
    guide
  };
}

function printPrereqSummary(prereq) {
  console.log("\nPrerequisite check");
  console.log(`- core tools: ${prereq.coreToolsOk ? "ok" : `missing ${prereq.missingRequired.join(", ")}`}`);
  console.log(`- worker backend (${prereq.workerCommand}): ${prereq.workerAvailable ? "found" : "missing on PATH"}`);
  console.log(`- GitHub auth: ${prereq.ghAuthOk ? "ok" : "not ready"}`);
  console.log(`- backend note: ${backendReadinessHint(prereq.workerCommand)}`);
}

function probeAnchorSyncReadiness(repoRoot) {
  if (!repoRoot || !fs.existsSync(repoRoot)) {
    return {
      status: "deferred",
      reason: "source-repo-missing",
      remoteUrl: "",
      details: ""
    };
  }

  const remoteResult = runCapture("git", ["remote", "get-url", "origin"], {
    cwd: repoRoot,
    timeoutMs: 5000
  });
  const remoteUrl = remoteResult.stdout.trim();
  if (remoteResult.status !== 0 || !remoteUrl) {
    return {
      status: "deferred",
      reason: "no-origin-remote",
      remoteUrl: "",
      details: `${remoteResult.stdout}${remoteResult.stderr}`.trim()
    };
  }

  const probeResult = runCapture("git", ["ls-remote", "--exit-code", "origin", "HEAD"], {
    cwd: repoRoot,
    timeoutMs: 15000
  });
  if (probeResult.status === 0) {
    return {
      status: "ready",
      reason: "",
      remoteUrl,
      details: ""
    };
  }

  const details = `${probeResult.stdout}${probeResult.stderr}`.trim();
  let reason = "git-remote-unreachable";
  if (probeResult.error && probeResult.error.code === "ETIMEDOUT") {
    reason = "git-remote-timeout";
  } else if (/could not read Username|Authentication failed|Permission denied|Repository not found|access denied|not found/i.test(details)) {
    reason = "git-remote-auth-or-access-error";
  } else if (/Could not resolve host|Name or service not known|Temporary failure in name resolution/i.test(details)) {
    reason = "git-remote-dns-error";
  }

  return {
    status: "deferred",
    reason,
    remoteUrl,
    details
  };
}

function buildAnchorSyncDecision(options, sourceRepoRoot) {
  if (options.skipAnchorSync) {
    return {
      status: "skipped",
      reason: "disabled",
      remoteUrl: "",
      details: "",
      skipAnchorSync: true
    };
  }

  const probe = probeAnchorSyncReadiness(sourceRepoRoot);
  if (probe.status === "ready") {
    return {
      status: "ok",
      reason: "",
      remoteUrl: probe.remoteUrl,
      details: probe.details,
      skipAnchorSync: false
    };
  }

  return {
    status: "deferred",
    reason: probe.reason,
    remoteUrl: probe.remoteUrl,
    details: probe.details,
    skipAnchorSync: true
  };
}

function profileExists(profileRegistryRoot, profileId) {
  return fs.existsSync(path.join(profileRegistryRoot, profileId, "control-plane.yaml"));
}

function buildScopedContext(context, profileId) {
  return {
    ...context,
    env: {
      ...context.env,
      ACP_PROJECT_ID: profileId,
      AGENT_PROJECT_ID: profileId
    }
  };
}

function renderSetupSummary(config) {
  console.log("\nSetup plan");
  console.log(`- profile id: ${config.profileId}`);
  console.log(`- repo slug: ${config.repoSlug}`);
  console.log(`- repo root: ${config.paths.repoRoot}`);
  console.log(`- agent root: ${config.paths.agentRoot}`);
  console.log(`- agent repo root: ${config.paths.agentRepoRoot}`);
  console.log(`- worktree root: ${config.paths.worktreeRoot}`);
  console.log(`- coding worker: ${config.codingWorker}`);
}

function planStatusWithReason(status, reason = "") {
  return {
    status,
    reason
  };
}

function buildSetupDryRunPlan(options, context, config) {
  const prereq = config.prereq;
  const dependencyPlan = buildDependencyInstallPlan(prereq.missingRequired);
  const workerInstallPlan = buildWorkerBackendInstallPlan(prereq.workerCommand);
  const workerGuide = backendSetupGuide(prereq.workerCommand);
  const anchorSync = buildAnchorSyncDecision(options, config.paths.sourceRepoRoot);

  let dependencyAction = planStatusWithReason("not-needed");
  if (!prereq.coreToolsOk) {
    if (options.installMissingDeps === false) {
      dependencyAction = planStatusWithReason("skipped", "disabled");
    } else if (!dependencyPlan) {
      dependencyAction = planStatusWithReason("unavailable", "no-supported-package-manager");
    } else if (options.installMissingDeps === true) {
      dependencyAction = planStatusWithReason("will-run");
    } else {
      dependencyAction = planStatusWithReason("would-prompt");
    }
  }

  let workerAction = planStatusWithReason("not-needed");
  if (!prereq.workerAvailable) {
    if (options.installMissingBackend === false) {
      workerAction = planStatusWithReason("skipped", "disabled");
    } else if (!workerInstallPlan) {
      workerAction = planStatusWithReason("unavailable", "no-supported-installer");
    } else if (options.installMissingBackend === true) {
      workerAction = planStatusWithReason("will-run");
    } else {
      workerAction = planStatusWithReason("would-prompt");
    }
  }

  let githubAuthAction = planStatusWithReason("not-needed");
  if (!prereq.ghAuthOk) {
    if (!commandExists("gh")) {
      githubAuthAction = planStatusWithReason("blocked", "gh-missing");
    } else if (options.ghAuthLogin === false) {
      githubAuthAction = planStatusWithReason("skipped", "disabled");
    } else if (options.ghAuthLogin === true) {
      githubAuthAction = planStatusWithReason("will-run");
    } else {
      githubAuthAction = planStatusWithReason("would-prompt");
    }
  }

  let runtimeStartAction = planStatusWithReason("skipped", "not-requested");
  if (config.startRuntime) {
    if (!prereq.coreToolsOk) {
      runtimeStartAction = planStatusWithReason("blocked", `missing-tools:${prereq.missingRequired.join(",")}`);
    } else if (!prereq.workerAvailable) {
      runtimeStartAction = planStatusWithReason("blocked", `missing-worker:${prereq.workerCommand}`);
    } else if (anchorSync.status !== "ok") {
      runtimeStartAction = planStatusWithReason("blocked", `anchor-sync-${anchorSync.reason}`);
    } else if (!prereq.ghAuthOk) {
      runtimeStartAction = planStatusWithReason("blocked", "gh-auth-not-ready");
    } else {
      runtimeStartAction = planStatusWithReason("would-run");
    }
  }

  let launchdAction = planStatusWithReason(process.platform === "darwin" ? "skipped" : "unsupported", process.platform === "darwin" ? "not-requested" : "non-macos");
  if (config.installLaunchd) {
    if (process.platform !== "darwin") {
      launchdAction = planStatusWithReason("unsupported", "non-macos");
    } else if (!config.startRuntime) {
      launchdAction = planStatusWithReason("blocked", "runtime-not-requested");
    } else if (runtimeStartAction.status !== "would-run") {
      launchdAction = planStatusWithReason("blocked", "runtime-not-ready");
    } else {
      launchdAction = planStatusWithReason("would-run");
    }
  }

  return {
    profileExists: profileExists(context.profileRegistryRoot, config.profileId),
    prereq,
    dependencyPlan,
    dependencyAction,
    workerInstallPlan,
    workerAction,
    workerGuide,
    anchorSync,
    githubAuthAction,
    runtimeStartAction,
    launchdAction
  };
}

function printSetupDryRunPlan(context, config, plan) {
  console.log("\nDry run plan");
  console.log(`- mode: dry-run`);
  console.log(`- profile exists already: ${plan.profileExists ? "yes" : "no"}`);
  console.log(`- runtime home: ${context.runtimeHome}`);
  console.log(`- profile registry root: ${context.profileRegistryRoot}`);
  console.log(`- sync packaged runtime: would-run`);
  console.log(`- scaffold/adopt profile: would-run`);
  console.log(`- anchor repo sync: ${plan.anchorSync.status === "ok" ? "would-run" : `${plan.anchorSync.status} (${plan.anchorSync.reason})`}`);
  console.log(`- doctor: would-run`);
  console.log(`- dependency install: ${plan.dependencyAction.status}${plan.dependencyAction.reason ? ` (${plan.dependencyAction.reason})` : ""}`);
  if (plan.dependencyAction.status !== "not-needed" && plan.dependencyPlan && plan.dependencyPlan.commands.length > 0) {
    console.log(`  command preview: ${plan.dependencyPlan.commands.map(formatCommand).join(" && ")}`);
  }
  console.log(`- worker backend install: ${plan.workerAction.status}${plan.workerAction.reason ? ` (${plan.workerAction.reason})` : ""}`);
  if (plan.workerAction.status !== "not-needed" && plan.workerInstallPlan && plan.workerInstallPlan.commands.length > 0) {
    console.log(`  command preview: ${plan.workerInstallPlan.commands.map(formatCommand).join(" && ")}`);
  }
  console.log(`- GitHub auth step: ${plan.githubAuthAction.status}${plan.githubAuthAction.reason ? ` (${plan.githubAuthAction.reason})` : ""}`);
  console.log(`- runtime start: ${plan.runtimeStartAction.status}${plan.runtimeStartAction.reason ? ` (${plan.runtimeStartAction.reason})` : ""}`);
  if (process.platform === "darwin") {
    console.log(`- launchd install: ${plan.launchdAction.status}${plan.launchdAction.reason ? ` (${plan.launchdAction.reason})` : ""}`);
  }
}

function buildSetupResultPayload(params) {
  return {
    setupStatus: params.setupStatus,
    setupMode: params.setupMode,
    profileId: params.profileId,
    repoSlug: params.repoSlug,
    codingWorker: params.codingWorker,
    profileExists: params.profileExists,
    paths: {
      repoRoot: params.repoRoot,
      agentRoot: params.agentRoot,
      agentRepoRoot: params.agentRepoRoot,
      worktreeRoot: params.worktreeRoot
    },
    coreTools: {
      status: params.coreToolsStatus,
      missingRequiredTools: params.missingRequiredTools
    },
    anchorSync: {
      status: params.anchorSyncStatus,
      reason: params.anchorSyncReason,
      remoteUrl: params.anchorSyncRemoteUrl
    },
    workerBackend: {
      command: params.workerBackendCommand,
      status: params.workerBackendStatus,
      setupGuideStatus: params.workerSetupGuideStatus,
      setupGuideReason: params.workerSetupGuideReason,
      installStatus: params.workerBackendInstallStatus,
      installReason: params.workerBackendInstallReason,
      installer: params.workerBackendInstaller,
      installCommand: params.workerBackendInstallCommand,
      docsOpened: params.workerSetupDocsOpened,
      docsUrl: params.workerBackendDocsUrl,
      installExample: params.workerBackendInstallExample,
      authExample: params.workerBackendAuthExample,
      verifyExample: params.workerBackendVerifyExample
    },
    githubAuth: {
      status: params.githubAuthStatus,
      stepStatus: params.githubAuthStepStatus,
      stepReason: params.githubAuthStepReason
    },
    dependencyInstall: {
      status: params.dependencyInstallStatus,
      reason: params.dependencyInstallReason,
      installer: params.dependencyInstaller,
      command: params.dependencyInstallCommand
    },
    projectInitStatus: params.projectInitStatus,
    doctorStatus: params.doctorStatus,
    runtime: {
      startStatus: params.runtimeStartStatus,
      startReason: params.runtimeStartReason,
      status: params.runtimeStatus
    },
    launchd: {
      status: params.launchdInstallStatus,
      reason: params.launchdInstallReason
    },
    finalFixup: {
      status: params.finalFixupStatus,
      actions: params.finalFixupActions
    }
  };
}

function emitSetupJsonPayload(payload) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
}

function collectFinalSetupIssues(config, prereq, doctorKv, runtimeStartStatus) {
  const issues = [];
  if (config.anchorSync && config.anchorSync.status !== "ok") {
    issues.push(`anchor repo sync ${config.anchorSync.status}: ${config.anchorSync.reason}`);
  }
  if (!prereq.coreToolsOk) {
    issues.push(`missing core tools: ${prereq.missingRequired.join(", ")}`);
  }
  if (!prereq.workerAvailable) {
    issues.push(`missing worker backend on PATH: ${prereq.workerCommand}`);
  }
  if (!prereq.ghAuthOk) {
    issues.push("GitHub CLI is not authenticated");
  }
  if ((doctorKv.DOCTOR_STATUS || "") !== "ok") {
    issues.push(`doctor status is ${doctorKv.DOCTOR_STATUS || "unknown"}`);
  }
  if (config.startRuntime && runtimeStartStatus !== "ok") {
    issues.push(`runtime start is ${runtimeStartStatus}`);
  }
  return issues;
}

async function maybeRunFinalSetupFixups(options, scopedContext, config, currentState) {
  const effectiveConfig = {
    ...config,
    anchorSync: currentState.anchorSync || config.anchorSync || null
  };
  const issues = collectFinalSetupIssues(effectiveConfig, currentState.prereq, currentState.doctorKv, currentState.runtimeStartStatus);
  if (issues.length === 0) {
    return {
      status: "not-needed",
      actions: [],
      ...currentState
    };
  }

  console.log("\nRemaining setup items");
  for (const issue of issues) {
    console.log(`- ${issue}`);
  }

  // Always show actionable hints so operators know what to fix,
  // even when running non-interactively (--yes / --json / CI).
  if (!currentState.prereq.coreToolsOk) {
    const missing = currentState.prereq.missingRequired.join(", ");
    console.log(`  Fix: install missing core tools (${missing})`);
  }
  if (!currentState.prereq.workerAvailable) {
    const worker = currentState.prereq.workerCommand;
    if (worker === "codex") console.log("  Fix: npm install -g @openai/codex && codex login");
    else if (worker === "openclaw") console.log("  Fix: npm install -g openclaw && openclaw setup");
    else if (worker === "claude") console.log("  Fix: npm install -g @anthropic-ai/claude-code && claude auth login");
    else console.log(`  Fix: install ${worker} and add it to PATH`);
  }
  if (!currentState.prereq.ghAuthOk) {
    console.log("  Fix: run gh auth login");
  }

  if (!options.interactive) {
    return {
      status: "skipped",
      actions: [],
      ...currentState
    };
  }

  const rl = createPromptInterface();
  let shouldFix = false;
  try {
    shouldFix = await promptYesNo(rl, "Run a final fix-up pass for the remaining items", true);
  } finally {
    rl.close();
  }

  if (!shouldFix) {
    return {
      status: "skipped",
      actions: [],
      ...currentState
    };
  }

  const actions = [];
  let prereq = currentState.prereq;
  let dependencyInstall = currentState.dependencyInstall;
  let githubAuthStep = currentState.githubAuthStep;
  let workerSetupStep = currentState.workerSetupStep;
  let doctorKv = currentState.doctorKv;
  let anchorSync = currentState.anchorSync || effectiveConfig.anchorSync || null;
  let runtimeStartStatus = currentState.runtimeStartStatus;
  let runtimeStartReason = currentState.runtimeStartReason;
  let runtimeStatusKv = currentState.runtimeStatusKv;
  let launchdInstallStatus = currentState.launchdInstallStatus;
  let launchdInstallReason = currentState.launchdInstallReason;

  if (!prereq.coreToolsOk) {
    actions.push("install-core-tools");
    dependencyInstall = await maybeInstallMissingDependencies({ ...options, installMissingDeps: true, interactive: false }, prereq);
    prereq = collectPrereqStatus(config.codingWorker);
  }

  if (!prereq.workerAvailable) {
    actions.push("install-worker-backend");
    workerSetupStep = await maybeShowWorkerSetupGuide({ ...options, installMissingBackend: true, interactive: options.interactive }, prereq);
    prereq = collectPrereqStatus(config.codingWorker);
  }

  if (!prereq.ghAuthOk) {
    actions.push("github-auth-login");
    githubAuthStep = await maybeRunGithubAuthLogin({ ...options, ghAuthLogin: true, interactive: false }, prereq);
    prereq = collectPrereqStatus(config.codingWorker);
  }

  if ((doctorKv.DOCTOR_STATUS || "") !== "ok") {
    actions.push("doctor-resync");
    runSetupStep(scopedContext, "Re-sync packaged runtime into ~/.agent-runtime", "tools/bin/sync-shared-agent-home.sh", []);
    const doctorOutput = runSetupStep(scopedContext, "Re-check runtime and profile health", "tools/bin/flow-runtime-doctor.sh", []);
    doctorKv = parseKvOutput(doctorOutput);
  }

  if (config.startRuntime && runtimeStartStatus !== "ok") {
    if (!prereq.coreToolsOk) {
      runtimeStartStatus = "skipped";
      runtimeStartReason = `missing-tools:${prereq.missingRequired.join(",")}`;
    } else if (!prereq.workerAvailable) {
      runtimeStartStatus = "skipped";
      runtimeStartReason = `missing-worker:${prereq.workerCommand}`;
    } else if (anchorSync && anchorSync.status !== "ok") {
      runtimeStartStatus = "skipped";
      runtimeStartReason = `anchor-sync-${anchorSync.reason}`;
    } else if (!prereq.ghAuthOk) {
      runtimeStartStatus = "skipped";
      runtimeStartReason = "gh-auth-not-ready";
    } else if ((doctorKv.DOCTOR_STATUS || "") !== "ok") {
      runtimeStartStatus = "skipped";
      runtimeStartReason = `doctor-${doctorKv.DOCTOR_STATUS || "not-ok"}`;
    } else {
      actions.push("runtime-start");
      runSetupStep(scopedContext, "Start the runtime", "tools/bin/project-runtimectl.sh", ["start", "--profile-id", config.profileId], { useRuntimeCopy: true });
      const runtimeStatusOutput = runSetupStep(scopedContext, "Read back runtime status", "tools/bin/project-runtimectl.sh", ["status", "--profile-id", config.profileId], { useRuntimeCopy: true });
      runtimeStatusKv = parseKvOutput(runtimeStatusOutput);
      runtimeStartStatus = "ok";
      runtimeStartReason = "";
    }
  }

  if (config.installLaunchd && process.platform === "darwin" && launchdInstallStatus !== "ok" && runtimeStartStatus === "ok") {
    actions.push("launchd-install");
    runSetupStep(scopedContext, "Install macOS autostart", "tools/bin/install-project-launchd.sh", ["--profile-id", config.profileId], { useRuntimeCopy: true });
    launchdInstallStatus = "ok";
    launchdInstallReason = "";
  }

  const finalIssues = collectFinalSetupIssues({ ...effectiveConfig, anchorSync }, prereq, doctorKv, runtimeStartStatus);
  let status = "ok";
  if (dependencyInstall.status === "failed" || githubAuthStep.status === "failed" || workerSetupStep.installStatus === "failed") {
    status = "failed";
  } else if (finalIssues.length > 0) {
    status = "remaining";
  }

  return {
    status,
    actions,
    anchorSync,
    prereq,
    dependencyInstall,
    githubAuthStep,
    workerSetupStep,
    doctorKv,
    runtimeStartStatus,
    runtimeStartReason,
    runtimeStatusKv,
    launchdInstallStatus,
    launchdInstallReason
  };
}

async function collectSetupConfig(options, context) {
  const detectedRepoRoot = path.resolve(options.repoRoot || detectRepoRoot(process.cwd()) || process.cwd());
  const detectedRepoSlug = options.repoSlug || detectRepoSlug(detectedRepoRoot);
  const suggestedProfileId = options.profileId || sanitizeProfileId((detectedRepoSlug.split("/").pop() || path.basename(detectedRepoRoot)));
  const suggestedWorker = options.codingWorker || detectPreferredWorker();

  let repoRoot = detectedRepoRoot;
  let repoSlug = detectedRepoSlug;
  let profileId = suggestedProfileId;
  let codingWorker = suggestedWorker;

  if (!fs.existsSync(detectedRepoRoot)) {
    throw new Error(`setup repo root does not exist: ${detectedRepoRoot}`);
  }

  if (!options.interactive) {
    if (!repoSlug) {
      throw new Error("setup could not detect --repo-slug automatically; pass --repo-slug <owner/repo> or run interactively inside a git checkout with origin set");
    }
  } else {
    printWizardBanner();
    const rl = createPromptInterface();
    try {
      printWizardStep(1, 4, "Project details");

      repoRoot = path.resolve(await promptText(rl, "Local repo root", detectedRepoRoot));
      repoSlug = await promptText(rl, "GitHub repo slug", repoSlug || "");
      profileId = sanitizeProfileId(await promptText(rl, "Profile id", profileId));

      let workerInput = codingWorker;
      while (!["codex", "claude", "openclaw"].includes(workerInput)) {
        workerInput = await promptText(rl, "Coding worker (codex / claude / openclaw)", codingWorker || "openclaw");
      }
      codingWorker = workerInput;
    } finally {
      rl.close();
    }
  }

  if (!["codex", "claude", "openclaw"].includes(codingWorker)) {
    throw new Error(`unsupported coding worker: ${codingWorker}`);
  }

  const paths = buildSetupPaths(context.platformHome, repoRoot, profileId, options);
  const prereq = collectPrereqStatus(codingWorker);
  const config = {
    profileId,
    repoSlug,
    repoRoot,
    codingWorker,
    paths,
    prereq
  };

  if (options.interactive) {
    printWizardStep(2, 4, "Review plan");
  }
  renderSetupSummary(config);

  if (options.interactive) {
    printPrereqSummary(prereq);
    const rl = createPromptInterface();
    try {
      if (!prereq.coreToolsOk || !prereq.workerAvailable || !prereq.ghAuthOk) {
        console.log("\nACP can still scaffold the profile now, but runtime start may be skipped until these checks are green.");
      }
      const shouldContinue = await promptYesNo(rl, "Continue with these values", true);
      if (!shouldContinue) {
        return null;
      }
      if (options.startRuntime === null) {
        options.startRuntime = await promptYesNo(rl, "Start the runtime after setup", true);
      }
      if (process.platform === "darwin" && options.installLaunchd === null && options.startRuntime) {
        options.installLaunchd = await promptYesNo(rl, "Install macOS autostart for this profile", false);
      }
    } finally {
      rl.close();
    }
  }

  if (options.startRuntime === null) {
    options.startRuntime = false;
  }
  if (options.installLaunchd === null) {
    options.installLaunchd = false;
  }

  return {
    ...config,
    startRuntime: Boolean(options.startRuntime),
    installLaunchd: Boolean(options.installLaunchd)
  };
}

function runSetupStep(context, title, scriptRelativePath, args, options = {}) {
  console.log(`\n== ${title} ==`);
  let executionContext = context;
  let scriptPath = undefined;

  if (options.useRuntimeCopy) {
    syncRuntimeHome(context, { stdio: "pipe" });
    executionContext = createRuntimeExecutionContext(context);
    scriptPath = path.join(executionContext.stableSkillRoot, scriptRelativePath);
  }

  const result = runScriptWithContext(executionContext, scriptRelativePath, args, {
    stdio: "pipe",
    env: options.env,
    cwd: options.cwd,
    scriptPath
  });
  if (result.status !== 0) {
    printFailureDetails(result);
    throw new Error(`${title} failed`);
  }
  return result.stdout || "";
}

async function runSetupFlow(forwardedArgs) {
  const jsonRequested = forwardedArgs.includes("--json");
  let options;
  try {
    options = parseSetupArgs(forwardedArgs);
  } catch (error) {
    if (jsonRequested) {
      emitSetupJsonPayload({
        setupStatus: "error",
        setupMode: "unknown",
        error: error.message
      });
    } else {
      console.error(error.message);
      printSetupHelp();
    }
    return 64;
  }

  if (options.help) {
    printSetupHelp();
    return 0;
  }

  const originalConsoleLog = console.log;
  const originalConsoleError = console.error;
  if (options.json) {
    setupJsonOutputEnabled = true;
    console.log = (...args) => {
      process.stderr.write(`${util.format(...args)}\n`);
    };
    console.error = (...args) => {
      process.stderr.write(`${util.format(...args)}\n`);
    };
  }

  const stage = stageSharedHome();
  const context = createExecutionContext(stage);

  try {
    const config = await collectSetupConfig(options, context);
    if (config === null) {
      console.log("\nSetup cancelled. Run again when you are ready.");
      return 0;
    }
    if (options.dryRun) {
      const plan = buildSetupDryRunPlan(options, context, config);
      printSetupDryRunPlan(context, config, plan);
      const dryRunWorkerBackendInstallCommand = plan.workerAction.status !== "not-needed" && plan.workerInstallPlan && plan.workerInstallPlan.commands.length > 0
        ? plan.workerInstallPlan.commands.map(formatCommand).join(" && ")
        : "";
      const dryRunDependencyInstallCommand = plan.dependencyAction.status !== "not-needed" && plan.dependencyPlan && plan.dependencyPlan.commands.length > 0
        ? plan.dependencyPlan.commands.map(formatCommand).join(" && ")
        : "";
      const dryRunPayload = buildSetupResultPayload({
        setupStatus: "dry-run",
        setupMode: "dry-run",
        profileId: config.profileId,
        repoSlug: config.repoSlug,
        codingWorker: config.codingWorker,
        profileExists: plan.profileExists,
        repoRoot: config.paths.repoRoot,
        agentRoot: config.paths.agentRoot,
        agentRepoRoot: config.paths.agentRepoRoot,
        worktreeRoot: config.paths.worktreeRoot,
        coreToolsStatus: plan.prereq.coreToolsOk ? "ok" : "missing",
        missingRequiredTools: plan.prereq.missingRequired,
        anchorSyncStatus: plan.anchorSync.status === "ok" ? "would-run" : plan.anchorSync.status,
        anchorSyncReason: plan.anchorSync.reason || "",
        anchorSyncRemoteUrl: plan.anchorSync.remoteUrl || "",
        workerBackendCommand: plan.prereq.workerCommand,
        workerBackendStatus: plan.prereq.workerAvailable ? "ok" : "missing",
        workerSetupGuideStatus: "planned",
        workerSetupGuideReason: plan.workerAction.reason || "",
        workerBackendInstallStatus: plan.workerAction.status,
        workerBackendInstallReason: plan.workerAction.reason || "",
        workerBackendInstaller: plan.workerInstallPlan ? plan.workerInstallPlan.installer : "",
        workerBackendInstallCommand: dryRunWorkerBackendInstallCommand,
        workerSetupDocsOpened: "planned",
        workerBackendDocsUrl: plan.workerGuide.docsUrl || "",
        workerBackendInstallExample: plan.workerGuide.installExamples[0] || "",
        workerBackendAuthExample: plan.workerGuide.authExamples[0] || "",
        workerBackendVerifyExample: plan.workerGuide.verifyExamples[0] || "",
        githubAuthStatus: plan.prereq.ghAuthOk ? "ok" : "not-ready",
        githubAuthStepStatus: plan.githubAuthAction.status,
        githubAuthStepReason: plan.githubAuthAction.reason || "",
        dependencyInstallStatus: plan.dependencyAction.status,
        dependencyInstallReason: plan.dependencyAction.reason || "",
        dependencyInstaller: plan.dependencyPlan ? plan.dependencyPlan.manager : "",
        dependencyInstallCommand: dryRunDependencyInstallCommand,
        projectInitStatus: "would-run",
        doctorStatus: "would-run",
        runtimeStartStatus: plan.runtimeStartAction.status,
        runtimeStartReason: plan.runtimeStartAction.reason || "",
        runtimeStatus: "",
        launchdInstallStatus: plan.launchdAction.status,
        launchdInstallReason: plan.launchdAction.reason || "",
        finalFixupStatus: "planned",
        finalFixupActions: ["review-plan"]
      });

      if (options.json) {
        emitSetupJsonPayload(dryRunPayload);
      } else {
        console.log(`SETUP_STATUS=dry-run`);
        console.log(`SETUP_MODE=dry-run`);
        console.log(`PROFILE_ID=${config.profileId}`);
        console.log(`REPO_SLUG=${config.repoSlug}`);
        console.log(`REPO_ROOT=${config.paths.repoRoot}`);
        console.log(`AGENT_ROOT=${config.paths.agentRoot}`);
        console.log(`AGENT_REPO_ROOT=${config.paths.agentRepoRoot}`);
        console.log(`WORKTREE_ROOT=${config.paths.worktreeRoot}`);
        console.log(`CODING_WORKER=${config.codingWorker}`);
        console.log(`PROFILE_EXISTS=${plan.profileExists ? "yes" : "no"}`);
        console.log(`CORE_TOOLS_STATUS=${plan.prereq.coreToolsOk ? "ok" : "missing"}`);
        console.log(`MISSING_REQUIRED_TOOLS=${plan.prereq.missingRequired.join(",")}`);
        console.log(`ANCHOR_SYNC_STATUS=${plan.anchorSync.status === "ok" ? "would-run" : plan.anchorSync.status}`);
        if (plan.anchorSync.reason) {
          console.log(`ANCHOR_SYNC_REASON=${plan.anchorSync.reason}`);
        }
        if (plan.anchorSync.remoteUrl) {
          console.log(`ANCHOR_SYNC_REMOTE_URL=${plan.anchorSync.remoteUrl}`);
        }
        console.log(`WORKER_BACKEND_COMMAND=${plan.prereq.workerCommand}`);
        console.log(`WORKER_BACKEND_STATUS=${plan.prereq.workerAvailable ? "ok" : "missing"}`);
        console.log(`GITHUB_AUTH_STATUS=${plan.prereq.ghAuthOk ? "ok" : "not-ready"}`);
        console.log(`DEPENDENCY_INSTALL_STATUS=${plan.dependencyAction.status}`);
        if (plan.dependencyAction.reason) {
          console.log(`DEPENDENCY_INSTALL_REASON=${plan.dependencyAction.reason}`);
        }
        if (plan.dependencyPlan && plan.dependencyPlan.commands.length > 0) {
          console.log(`DEPENDENCY_INSTALL_COMMAND=${plan.dependencyPlan.commands.map(formatCommand).join(" && ")}`);
        }
        console.log(`WORKER_BACKEND_INSTALL_STATUS=${plan.workerAction.status}`);
        if (plan.workerAction.reason) {
          console.log(`WORKER_BACKEND_INSTALL_REASON=${plan.workerAction.reason}`);
        }
        if (plan.workerInstallPlan && plan.workerInstallPlan.installer) {
          console.log(`WORKER_BACKEND_INSTALLER=${plan.workerInstallPlan.installer}`);
        }
        if (plan.workerInstallPlan && plan.workerInstallPlan.commands.length > 0) {
          console.log(`WORKER_BACKEND_INSTALL_COMMAND=${plan.workerInstallPlan.commands.map(formatCommand).join(" && ")}`);
        }
        if (plan.workerGuide.docsUrl) {
          console.log(`WORKER_BACKEND_DOCS_URL=${plan.workerGuide.docsUrl}`);
        }
        if (plan.workerGuide.installExamples[0]) {
          console.log(`WORKER_BACKEND_INSTALL_EXAMPLE=${plan.workerGuide.installExamples[0]}`);
        }
        if (plan.workerGuide.authExamples[0]) {
          console.log(`WORKER_BACKEND_AUTH_EXAMPLE=${plan.workerGuide.authExamples[0]}`);
        }
        if (plan.workerGuide.verifyExamples[0]) {
          console.log(`WORKER_BACKEND_VERIFY_EXAMPLE=${plan.workerGuide.verifyExamples[0]}`);
        }
        console.log(`GITHUB_AUTH_STEP_STATUS=${plan.githubAuthAction.status}`);
        if (plan.githubAuthAction.reason) {
          console.log(`GITHUB_AUTH_STEP_REASON=${plan.githubAuthAction.reason}`);
        }
        console.log(`PROJECT_INIT_STATUS=would-run`);
        console.log(`DOCTOR_STATUS=would-run`);
        console.log(`RUNTIME_START_STATUS=${plan.runtimeStartAction.status}`);
        if (plan.runtimeStartAction.reason) {
          console.log(`RUNTIME_START_REASON=${plan.runtimeStartAction.reason}`);
        }
        console.log(`LAUNCHD_INSTALL_STATUS=${plan.launchdAction.status}`);
        if (plan.launchdAction.reason) {
          console.log(`LAUNCHD_INSTALL_REASON=${plan.launchdAction.reason}`);
        }
        console.log(`FINAL_FIXUP_STATUS=planned`);
        console.log(`FINAL_FIXUP_ACTIONS=review-plan`);
      }
      return 0;
    }

    if (profileExists(context.profileRegistryRoot, config.profileId) && !options.force) {
      console.error(`setup found an existing profile at ${path.join(context.profileRegistryRoot, config.profileId)}.`);
      console.error("Re-run with --force if you want to overwrite it.");
      return 1;
    }

    if (options.interactive) {
      printWizardStep(3, 4, "Prerequisites");
    }

    let prereq = config.prereq;
    let dependencyInstall = await maybeInstallMissingDependencies(options, prereq);
    if (dependencyInstall.status === "failed") {
      console.error("dependency installation failed");
      return 1;
    }
    prereq = collectPrereqStatus(config.codingWorker);

    let githubAuthStep = await maybeRunGithubAuthLogin(options, prereq);
    if (githubAuthStep.status === "failed") {
      console.error("GitHub authentication failed");
      return 1;
    }
    prereq = collectPrereqStatus(config.codingWorker);
    let workerSetupStep = await maybeShowWorkerSetupGuide(options, prereq);
    prereq = collectPrereqStatus(config.codingWorker);

    // Check OpenRouter API key when openclaw is selected
    if (config.codingWorker === "openclaw" && !process.env.OPENROUTER_API_KEY) {
      console.log("\nOpenClaw requires an OpenRouter API key (OPENROUTER_API_KEY).");
      console.log("- Get a free key at: https://openrouter.ai/keys");
      if (options.interactive) {
        const rl = createPromptInterface();
        let apiKey = "";
        try {
          apiKey = (await promptText(rl, "OpenRouter API key (Enter to skip)", "")).trim();
        } finally {
          rl.close();
        }
        if (apiKey) {
          process.env.OPENROUTER_API_KEY = apiKey;
          console.log("API key set for this session.");
          console.log("To persist it, add the following to your shell profile (~/.zshrc or ~/.bashrc):");
          console.log(`  export OPENROUTER_API_KEY=${JSON.stringify(apiKey)}`);
        } else {
          console.log("Skipped. Set OPENROUTER_API_KEY before starting the runtime.");
        }
      } else {
        console.log("Set OPENROUTER_API_KEY in your environment before starting the runtime.");
      }
    }

    if (options.interactive) {
      printWizardStep(4, 4, "Install");
    }

    const scopedContext = buildScopedContext(context, config.profileId);
    const anchorSync = buildAnchorSyncDecision(options, config.paths.sourceRepoRoot);

    if (anchorSync.status === "deferred") {
      console.log("\nAnchor repo sync will be deferred for this setup run.");
      if (anchorSync.remoteUrl) {
        console.log(`- remote: ${anchorSync.remoteUrl}`);
      }
      console.log(`- reason: ${anchorSync.reason}`);
      console.log("- next step: authenticate Git access or fix the repo remote, then rerun `setup` or `init` without skipping anchor sync.");
    }

    runSetupStep(scopedContext, "Sync packaged runtime into ~/.agent-runtime", "tools/bin/sync-shared-agent-home.sh", []);

    const initArgs = [
      "--profile-id", config.profileId,
      "--repo-slug", config.repoSlug,
      "--repo-root", config.paths.repoRoot,
      "--agent-root", config.paths.agentRoot,
      "--agent-repo-root", config.paths.agentRepoRoot,
      "--worktree-root", config.paths.worktreeRoot,
      "--retained-repo-root", config.paths.retainedRepoRoot,
      "--vscode-workspace-file", config.paths.vscodeWorkspaceFile,
      "--source-repo-root", config.paths.sourceRepoRoot,
      "--coding-worker", config.codingWorker
    ];
    if (options.force) {
      initArgs.push("--force");
    }
    if (anchorSync.skipAnchorSync) {
      initArgs.push("--skip-anchor-sync");
    }
    if (options.skipWorkspaceSync) {
      initArgs.push("--skip-workspace-sync");
    }
    if (options.allowMissingRepo) {
      initArgs.push("--allow-missing-repo");
    }

    const initOutput = runSetupStep(scopedContext, "Scaffold and adopt the project profile", "tools/bin/project-init.sh", initArgs);
    const initKv = parseKvOutput(initOutput);

    const doctorOutput = runSetupStep(scopedContext, "Check runtime and profile health", "tools/bin/flow-runtime-doctor.sh", []);
    let doctorKv = parseKvOutput(doctorOutput);

    let runtimeStartStatus = "skipped";
    let runtimeStartReason = "not-requested";
    let runtimeStatusKv = {};

    if (config.startRuntime) {
      if (prereq.missingRequired.length > 0) {
        runtimeStartReason = `missing-tools:${prereq.missingRequired.join(",")}`;
        console.log(`runtime start skipped: missing required tools (${prereq.missingRequired.join(", ")})`);
      } else if (!prereq.workerAvailable) {
        runtimeStartReason = `missing-worker:${prereq.workerCommand}`;
        console.log(`runtime start skipped: ${prereq.workerCommand} is not available on PATH`);
      } else if (anchorSync.status !== "ok") {
        runtimeStartReason = `anchor-sync-${anchorSync.reason}`;
        console.log("runtime start skipped: ACP deferred anchor repo sync for this setup run.");
      } else if (!prereq.ghAuthOk) {
        runtimeStartReason = "gh-auth-not-ready";
        console.log("runtime start skipped: GitHub CLI is not authenticated yet. Run `gh auth login` and start the runtime afterwards.");
      } else {
        runSetupStep(scopedContext, "Start the runtime", "tools/bin/project-runtimectl.sh", ["start", "--profile-id", config.profileId], { useRuntimeCopy: true });
        const runtimeStatusOutput = runSetupStep(scopedContext, "Read back runtime status", "tools/bin/project-runtimectl.sh", ["status", "--profile-id", config.profileId], { useRuntimeCopy: true });
        runtimeStatusKv = parseKvOutput(runtimeStatusOutput);
        runtimeStartStatus = "ok";
        runtimeStartReason = "";
      }
    }

    let launchdInstallStatus = "skipped";
    let launchdInstallReason = process.platform === "darwin" ? "not-requested" : "non-macos";

    if (config.installLaunchd) {
      if (process.platform !== "darwin") {
        console.log("launchd install skipped: this command is only relevant on macOS.");
      } else if (runtimeStartStatus !== "ok") {
        launchdInstallReason = "runtime-not-started";
        console.log("launchd install skipped: runtime was not started successfully in this setup run.");
      } else {
        runSetupStep(scopedContext, "Install macOS autostart", "tools/bin/install-project-launchd.sh", ["--profile-id", config.profileId], { useRuntimeCopy: true });
        launchdInstallStatus = "ok";
        launchdInstallReason = "";
      }
    }

    const finalFixup = await maybeRunFinalSetupFixups(options, scopedContext, config, {
      anchorSync,
      prereq,
      dependencyInstall,
      githubAuthStep,
      workerSetupStep,
      doctorKv,
      runtimeStartStatus,
      runtimeStartReason,
      runtimeStatusKv,
      launchdInstallStatus,
      launchdInstallReason
    });

    prereq = finalFixup.prereq;
    dependencyInstall = finalFixup.dependencyInstall;
    githubAuthStep = finalFixup.githubAuthStep;
    workerSetupStep = finalFixup.workerSetupStep;
    doctorKv = finalFixup.doctorKv;
    runtimeStartStatus = finalFixup.runtimeStartStatus;
    runtimeStartReason = finalFixup.runtimeStartReason;
    runtimeStatusKv = finalFixup.runtimeStatusKv;
    launchdInstallStatus = finalFixup.launchdInstallStatus;
    launchdInstallReason = finalFixup.launchdInstallReason;

    const runPayload = buildSetupResultPayload({
      setupStatus: "ok",
      setupMode: "run",
      profileId: config.profileId,
      repoSlug: config.repoSlug,
      codingWorker: config.codingWorker,
      profileExists: true,
      repoRoot: config.paths.repoRoot,
      agentRoot: config.paths.agentRoot,
      agentRepoRoot: config.paths.agentRepoRoot,
      worktreeRoot: config.paths.worktreeRoot,
      coreToolsStatus: prereq.coreToolsOk ? "ok" : "missing",
      missingRequiredTools: prereq.missingRequired,
      anchorSyncStatus: anchorSync.status,
      anchorSyncReason: anchorSync.reason || "",
      anchorSyncRemoteUrl: anchorSync.remoteUrl || "",
      workerBackendCommand: prereq.workerCommand,
      workerBackendStatus: prereq.workerAvailable ? "ok" : "missing",
      workerSetupGuideStatus: workerSetupStep.status,
      workerSetupGuideReason: workerSetupStep.reason || "",
      workerBackendInstallStatus: workerSetupStep.installStatus,
      workerBackendInstallReason: workerSetupStep.installReason || "",
      workerBackendInstaller: workerSetupStep.installer || "",
      workerBackendInstallCommand: workerSetupStep.commands.length > 0 ? workerSetupStep.commands.map(formatCommand).join(" && ") : "",
      workerSetupDocsOpened: workerSetupStep.docsOpened,
      workerBackendDocsUrl: workerSetupStep.guide.docsUrl || "",
      workerBackendInstallExample: workerSetupStep.guide.installExamples[0] || "",
      workerBackendAuthExample: workerSetupStep.guide.authExamples[0] || "",
      workerBackendVerifyExample: workerSetupStep.guide.verifyExamples[0] || "",
      githubAuthStatus: prereq.ghAuthOk ? "ok" : "not-ready",
      githubAuthStepStatus: githubAuthStep.status,
      githubAuthStepReason: githubAuthStep.reason || "",
      dependencyInstallStatus: dependencyInstall.status,
      dependencyInstallReason: dependencyInstall.reason || "",
      dependencyInstaller: dependencyInstall.installer || "",
      dependencyInstallCommand: dependencyInstall.commands.length > 0 ? dependencyInstall.commands.map(formatCommand).join(" && ") : "",
      projectInitStatus: initKv.PROJECT_INIT_STATUS || "ok",
      doctorStatus: doctorKv.DOCTOR_STATUS || "",
      runtimeStartStatus,
      runtimeStartReason: runtimeStartReason || "",
      runtimeStatus: runtimeStatusKv.RUNTIME_STATUS || "",
      launchdInstallStatus,
      launchdInstallReason: launchdInstallReason || "",
      finalFixupStatus: finalFixup.status,
      finalFixupActions: finalFixup.actions
    });

    if (options.json) {
      emitSetupJsonPayload(runPayload);
    } else if (options.interactive) {
      // Human-friendly summary for interactive terminal runs
      console.log("\n============================================================");
      console.log("  Setup complete!");
      console.log("============================================================");
      console.log(`  Profile : ${config.profileId}`);
      console.log(`  Repo    : ${config.repoSlug}`);
      console.log(`  Worker  : ${config.codingWorker}`);
      console.log(`  Runtime : ${context.runtimeHome}`);

      const pendingItems = [];
      if (!prereq.ghAuthOk) pendingItems.push("GitHub CLI not authenticated — run: gh auth login");
      if (!prereq.workerAvailable) pendingItems.push(`${config.codingWorker} not found on PATH — install it before starting`);
      if (config.codingWorker === "openclaw" && !process.env.OPENROUTER_API_KEY) {
        pendingItems.push("OPENROUTER_API_KEY not set — required for openclaw workers");
      }
      if (anchorSync.status !== "ok") pendingItems.push(`Anchor repo sync deferred (${anchorSync.reason}) — fix git access and re-run setup`);
      if ((doctorKv.DOCTOR_STATUS || "") !== "ok") pendingItems.push(`Doctor check flagged issues — run: npx agent-control-plane@latest doctor`);

      if (pendingItems.length > 0) {
        console.log("\n  Pending items before starting:");
        for (const item of pendingItems) {
          console.log(`    - ${item}`);
        }
      }

      console.log("\n  Next commands:");
      if (runtimeStartStatus !== "ok") {
        console.log(`    npx agent-control-plane@latest runtime start --profile-id ${config.profileId}`);
      }
      console.log(`    npx agent-control-plane@latest runtime status --profile-id ${config.profileId}`);
      console.log(`    npx agent-control-plane@latest doctor`);
      console.log("");
    } else {
      // Machine-readable KV output for non-interactive / scripted runs
      console.log("\nSetup complete.");
      console.log(`- profile: ${config.profileId}`);
      console.log(`- repo: ${config.repoSlug}`);
      console.log(`- runtime home: ${context.runtimeHome}`);

      console.log(`SETUP_STATUS=ok`);
      console.log(`PROFILE_ID=${config.profileId}`);
      console.log(`REPO_SLUG=${config.repoSlug}`);
      console.log(`REPO_ROOT=${config.paths.repoRoot}`);
      console.log(`AGENT_ROOT=${config.paths.agentRoot}`);
      console.log(`AGENT_REPO_ROOT=${config.paths.agentRepoRoot}`);
      console.log(`WORKTREE_ROOT=${config.paths.worktreeRoot}`);
      console.log(`CODING_WORKER=${config.codingWorker}`);
      console.log(`CORE_TOOLS_STATUS=${prereq.coreToolsOk ? "ok" : "missing"}`);
      console.log(`MISSING_REQUIRED_TOOLS=${prereq.missingRequired.join(",")}`);
      console.log(`ANCHOR_SYNC_STATUS=${anchorSync.status}`);
      if (anchorSync.reason) {
        console.log(`ANCHOR_SYNC_REASON=${anchorSync.reason}`);
      }
      if (anchorSync.remoteUrl) {
        console.log(`ANCHOR_SYNC_REMOTE_URL=${anchorSync.remoteUrl}`);
      }
      console.log(`WORKER_BACKEND_COMMAND=${prereq.workerCommand}`);
      console.log(`WORKER_BACKEND_STATUS=${prereq.workerAvailable ? "ok" : "missing"}`);
      console.log(`WORKER_SETUP_GUIDE_STATUS=${workerSetupStep.status}`);
      if (workerSetupStep.reason) {
        console.log(`WORKER_SETUP_GUIDE_REASON=${workerSetupStep.reason}`);
      }
      console.log(`WORKER_BACKEND_INSTALL_STATUS=${workerSetupStep.installStatus}`);
      if (workerSetupStep.installReason) {
        console.log(`WORKER_BACKEND_INSTALL_REASON=${workerSetupStep.installReason}`);
      }
      if (workerSetupStep.installer) {
        console.log(`WORKER_BACKEND_INSTALLER=${workerSetupStep.installer}`);
      }
      if (workerSetupStep.commands.length > 0) {
        console.log(`WORKER_BACKEND_INSTALL_COMMAND=${workerSetupStep.commands.map(formatCommand).join(" && ")}`);
      }
      console.log(`WORKER_SETUP_DOCS_OPENED=${workerSetupStep.docsOpened}`);
      if (workerSetupStep.guide.docsUrl) {
        console.log(`WORKER_BACKEND_DOCS_URL=${workerSetupStep.guide.docsUrl}`);
      }
      if (workerSetupStep.guide.installExamples[0]) {
        console.log(`WORKER_BACKEND_INSTALL_EXAMPLE=${workerSetupStep.guide.installExamples[0]}`);
      }
      if (workerSetupStep.guide.authExamples[0]) {
        console.log(`WORKER_BACKEND_AUTH_EXAMPLE=${workerSetupStep.guide.authExamples[0]}`);
      }
      if (workerSetupStep.guide.verifyExamples[0]) {
        console.log(`WORKER_BACKEND_VERIFY_EXAMPLE=${workerSetupStep.guide.verifyExamples[0]}`);
      }
      console.log(`GITHUB_AUTH_STATUS=${prereq.ghAuthOk ? "ok" : "not-ready"}`);
      console.log(`FINAL_FIXUP_STATUS=${finalFixup.status}`);
      console.log(`FINAL_FIXUP_ACTIONS=${finalFixup.actions.join(",")}`);
      console.log(`DEPENDENCY_INSTALL_STATUS=${dependencyInstall.status}`);
      if (dependencyInstall.reason) {
        console.log(`DEPENDENCY_INSTALL_REASON=${dependencyInstall.reason}`);
      }
      if (dependencyInstall.installer) {
        console.log(`DEPENDENCY_INSTALLER=${dependencyInstall.installer}`);
      }
      if (dependencyInstall.commands.length > 0) {
        console.log(`DEPENDENCY_INSTALL_COMMAND=${dependencyInstall.commands.map(formatCommand).join(" && ")}`);
      }
      console.log(`GITHUB_AUTH_STEP_STATUS=${githubAuthStep.status}`);
      if (githubAuthStep.reason) {
        console.log(`GITHUB_AUTH_STEP_REASON=${githubAuthStep.reason}`);
      }
      console.log(`PROJECT_INIT_STATUS=${initKv.PROJECT_INIT_STATUS || "ok"}`);
      console.log(`DOCTOR_STATUS=${doctorKv.DOCTOR_STATUS || ""}`);
      console.log(`RUNTIME_START_STATUS=${runtimeStartStatus}`);
      if (runtimeStartReason) {
        console.log(`RUNTIME_START_REASON=${runtimeStartReason}`);
      }
      console.log(`LAUNCHD_INSTALL_STATUS=${launchdInstallStatus}`);
      if (launchdInstallReason) {
        console.log(`LAUNCHD_INSTALL_REASON=${launchdInstallReason}`);
      }
      if (runtimeStatusKv.RUNTIME_STATUS) {
        console.log(`RUNTIME_STATUS=${runtimeStatusKv.RUNTIME_STATUS}`);
      }
    }

    return 0;
  } catch (error) {
    if (options.json) {
      emitSetupJsonPayload({
        setupStatus: "error",
        setupMode: options.dryRun ? "dry-run" : "run",
        error: error && error.message ? error.message : String(error)
      });
    } else if (error && error.message) {
      console.error(error.message);
    }
    return 1;
  } finally {
    if (options.json) {
      console.log = originalConsoleLog;
      console.error = originalConsoleError;
      setupJsonOutputEnabled = false;
    }
    fs.rmSync(stage.stageRoot, { recursive: true, force: true });
  }
}

async function main() {
  const command = process.argv[2] || "help";
  const forwardedArgs = process.argv.slice(3);

  switch (command) {
    case "help":
    case "--help":
    case "-h":
      printHelp();
      return 0;
    case "version":
    case "--version":
    case "-v":
      console.log(packageJson.version);
      return 0;
    case "setup":
    case "onboard":
      return runSetupFlow(forwardedArgs);
    case "sync":
    case "install":
      return runCommand("tools/bin/sync-shared-agent-home.sh", forwardedArgs);
    case "init":
      return runCommand("tools/bin/project-init.sh", forwardedArgs);
    case "doctor":
      return runCommand("tools/bin/flow-runtime-doctor.sh", forwardedArgs);
    case "profile-smoke":
      return runCommand("tools/bin/profile-smoke.sh", forwardedArgs);
    case "dashboard":
      return runCommand("tools/bin/serve-dashboard.sh", forwardedArgs);
    case "launchd-install":
      return runCommand("tools/bin/install-project-launchd.sh", forwardedArgs);
    case "launchd-uninstall":
      return runCommand("tools/bin/uninstall-project-launchd.sh", forwardedArgs);
    case "runtime":
      return runCommand("tools/bin/project-runtimectl.sh", forwardedArgs);
    case "remove":
      return runCommand("tools/bin/project-remove.sh", forwardedArgs);
    case "smoke":
      return runCommand("tools/bin/test-smoke.sh", forwardedArgs);
    default:
      console.error(`unknown command: ${command}`);
      console.error("run `agent-control-plane help` for usage");
      return 64;
  }
}

main()
  .then((status) => {
    process.exit(status);
  })
  .catch((error) => {
    console.error(error && error.message ? error.message : String(error));
    process.exit(1);
  });
