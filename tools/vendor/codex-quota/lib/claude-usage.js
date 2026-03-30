/**
 * Claude usage API fetch (OAuth only).
 * Depends on: lib/constants.js, lib/paths.js, lib/claude-accounts.js, lib/claude-tokens.js
 */

import { existsSync, readFileSync } from "node:fs";
import {
	CLAUDE_MULTI_ACCOUNT_PATHS,
	CLAUDE_TIMEOUT_MS,
	CLAUDE_OAUTH_USAGE_URL,
	CLAUDE_OAUTH_VERSION,
	CLAUDE_OAUTH_BETA,
} from "./constants.js";
import { getOpencodeAuthPath } from "./paths.js";
import {
	loadClaudeAccountsFromFile,
	loadClaudeOAuthToken,
} from "./claude-accounts.js";
import { ensureFreshClaudeOAuthToken } from "./claude-tokens.js";

export function normalizeClaudeOrgId(orgId) {
	if (!orgId || typeof orgId !== "string") return orgId;
	if (/^[0-9a-f-]{36}$/i.test(orgId)) {
		return orgId.replace(/-/g, "");
	}
	return orgId;
}

export function isClaudeAuthError(error) {
	if (!error) return false;
	return /invalid authorization|http 401|http 403/i.test(String(error));
}

export function loadClaudeOAuthFromClaudeCode() {
	const credentials = loadClaudeOAuthToken();
	if (!credentials.token) return [];

	let scopes = [];
	let refreshToken = null;
	let expiresAt = null;
	let subscriptionType = null;
	let rateLimitTier = null;

	try {
		const raw = readFileSync(credentials.source, "utf-8");
		const parsed = JSON.parse(raw);
		const oauth = parsed?.claudeAiOauth ?? parsed?.claude_ai_oauth ?? null;
		scopes = Array.isArray(oauth?.scopes) ? oauth.scopes : [];
		refreshToken = oauth?.refreshToken ?? null;
		expiresAt = oauth?.expiresAt ?? null;
		subscriptionType = oauth?.subscriptionType ?? null;
		rateLimitTier = oauth?.rateLimitTier ?? null;
	} catch {
		// Ignore parse failures and return the token-only shape.
	}

	if (!scopes.includes("user:profile")) {
		return [];
	}

	return [{
		label: "claude-code",
		accessToken: credentials.token,
		refreshToken,
		expiresAt,
		subscriptionType,
		rateLimitTier,
		scopes,
		source: credentials.source,
	}];
}

/**
 * Load Claude OAuth account from OpenCode auth.json
 * @returns {Array<{ label: string, accessToken: string, refreshToken?: string, expiresAt?: number, source: string }>}
 */
export function loadClaudeOAuthFromOpenCode() {
	const authPath = getOpencodeAuthPath();
	if (!existsSync(authPath)) return [];

	try {
		const raw = readFileSync(authPath, "utf-8");
		const parsed = JSON.parse(raw);
		const anthropic = parsed?.anthropic;

		if (!anthropic?.access) return [];

		return [{
			label: "opencode",
			accessToken: anthropic.access,
			refreshToken: anthropic.refresh,
			expiresAt: anthropic.expires,
			source: authPath,
		}];
	} catch {
		return [];
	}
}

/**
 * Load Claude OAuth accounts from environment variable
 * Format: JSON array with { label, accessToken, refreshToken?, ... }
 * @returns {Array<{ label: string, accessToken: string, ... }>}
 */
export function loadClaudeOAuthFromEnv() {
	const envAccounts = process.env.CLAUDE_OAUTH_ACCOUNTS;
	if (!envAccounts) return [];

	try {
		const parsed = JSON.parse(envAccounts);
		const accounts = Array.isArray(parsed) ? parsed : parsed?.accounts ?? [];
		return accounts
			.filter(a => a?.label && a?.accessToken)
			.map(a => ({ ...a, source: "env:CLAUDE_OAUTH_ACCOUNTS" }));
	} catch {
		return [];
	}
}

/**
 * Deduplicate Claude OAuth accounts by refresh token
 * This handles the case where the same Claude account is sourced from multiple files.
 */
export function deduplicateClaudeOAuthAccounts(accounts) {
	const seenTokens = new Set();
	return accounts.filter(account => {
		if (!account.accessToken) return true;
		const tokenKey = account.refreshToken
			? account.refreshToken.substring(0, 50)
			: account.accessToken.substring(0, 50);
		if (seenTokens.has(tokenKey)) return false;
		seenTokens.add(tokenKey);
		return true;
	});
}

/**
 * Deduplicate Claude usage results by comparing usage fingerprints.
 */
export function deduplicateClaudeResultsByUsage(results) {
	const seen = new Set();
	return results.filter(result => {
		if (!result.success || !result.usage) return true;

		const usage = result.usage;
		const fiveHour = usage.five_hour?.utilization ?? "null";
		const sevenDay = usage.seven_day?.utilization ?? "null";
		const sevenDayOpus = usage.seven_day_opus?.utilization ?? "null";
		const sevenDaySonnet = usage.seven_day_sonnet?.utilization ?? "null";
		const fingerprint = `${fiveHour}|${sevenDay}|${sevenDayOpus}|${sevenDaySonnet}`;

		if (seen.has(fingerprint)) return false;
		seen.add(fingerprint);
		return true;
	});
}

/**
 * Load all Claude OAuth accounts from all supported sources.
 */
export function loadAllClaudeOAuthAccounts(options = {}) {
	const all = [];
	const seenLabels = new Set();

	for (const account of loadClaudeOAuthFromEnv()) {
		if (!seenLabels.has(account.label)) {
			seenLabels.add(account.label);
			all.push(account);
		}
	}

	for (const path of CLAUDE_MULTI_ACCOUNT_PATHS) {
		const accounts = loadClaudeAccountsFromFile(path);
		for (const account of accounts) {
			if (account.oauthToken && !seenLabels.has(account.label)) {
				seenLabels.add(account.label);
				all.push({
					label: account.label,
					accessToken: account.oauthToken,
					refreshToken: account.oauthRefreshToken || null,
					expiresAt: account.oauthExpiresAt || null,
					scopes: account.oauthScopes || null,
					source: account.source,
				});
			}
		}
	}

	if (!options.local) {
		for (const account of loadClaudeOAuthFromClaudeCode()) {
			if (!seenLabels.has(account.label)) {
				seenLabels.add(account.label);
				all.push(account);
			}
		}
		for (const account of loadClaudeOAuthFromOpenCode()) {
			if (!seenLabels.has(account.label)) {
				seenLabels.add(account.label);
				all.push(account);
			}
		}
	}

	return deduplicateClaudeOAuthAccounts(all);
}

/**
 * Fetch Claude usage via OAuth API.
 */
export async function fetchClaudeOAuthUsage(accessToken) {
	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), CLAUDE_TIMEOUT_MS);

	try {
		const res = await fetch(CLAUDE_OAUTH_USAGE_URL, {
			method: "GET",
			headers: {
				Authorization: `Bearer ${accessToken}`,
				"anthropic-version": CLAUDE_OAUTH_VERSION,
				"anthropic-beta": CLAUDE_OAUTH_BETA,
			},
			signal: controller.signal,
		});

		if (!res.ok) {
			const body = await res.text().catch(() => "");
			return {
				success: false,
				error: `HTTP ${res.status}: ${body.slice(0, 200) || res.statusText}`,
			};
		}

		const data = await res.json();
		return { success: true, data };
	} catch (err) {
		const message = err.name === "AbortError" ? "Request timed out" : err.message;
		return { success: false, error: message };
	} finally {
		clearTimeout(timeout);
	}
}

/**
 * Fetch usage for a Claude OAuth account.
 */
export async function fetchClaudeOAuthUsageForAccount(account) {
	const refreshed = await ensureFreshClaudeOAuthToken(account);
	if (!refreshed) {
		const message = account.refreshToken
			? "OAuth token expired and refresh failed - run 'claude /login'"
			: "OAuth token expired - refresh token missing, run 'claude /login'";
		return {
			success: false,
			label: account.label,
			source: account.source,
			error: message,
			subscriptionType: account.subscriptionType,
			rateLimitTier: account.rateLimitTier,
		};
	}

	const result = await fetchClaudeOAuthUsage(account.accessToken);
	if (!result.success) {
		return {
			success: false,
			label: account.label,
			source: account.source,
			error: result.error,
			subscriptionType: account.subscriptionType,
			rateLimitTier: account.rateLimitTier,
		};
	}

	return {
		success: true,
		label: account.label,
		source: account.source,
		usage: result.data,
		subscriptionType: account.subscriptionType,
		rateLimitTier: account.rateLimitTier,
	};
}

/**
 * Backward-compatible wrapper for stored Claude credentials.
 * Only OAuth-backed credentials are supported.
 */
export async function fetchClaudeUsageForCredentials(credentials) {
	if (!credentials?.oauthToken) {
		return {
			success: false,
			label: credentials?.label ?? null,
			source: credentials?.source ?? null,
			error: "Claude OAuth token required",
		};
	}

	return fetchClaudeOAuthUsageForAccount({
		label: credentials.label ?? null,
		source: credentials.source ?? null,
		accessToken: credentials.oauthToken,
		refreshToken: credentials.oauthRefreshToken ?? null,
		expiresAt: credentials.oauthExpiresAt ?? null,
		scopes: credentials.oauthScopes ?? null,
		subscriptionType: credentials.subscriptionType,
		rateLimitTier: credentials.rateLimitTier,
	});
}

/**
 * Backward-compatible wrapper for Claude Code credentials.
 * Only OAuth-backed credentials are supported.
 */
export async function fetchClaudeUsage() {
	const oauth = loadClaudeOAuthToken();
	if (!oauth.token) {
		return {
			success: false,
			source: oauth.source,
			error: oauth.error ?? "Claude OAuth token required",
		};
	}

	const result = await fetchClaudeOAuthUsage(oauth.token);
	if (!result.success) {
		return {
			success: false,
			source: oauth.source,
			error: result.error,
		};
	}

	return {
		success: true,
		source: oauth.source,
		usage: result.data,
	};
}
