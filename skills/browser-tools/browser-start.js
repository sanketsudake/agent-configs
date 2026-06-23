#!/usr/bin/env node

import { spawn, execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import puppeteer from "puppeteer-core";

const CHROME_DIR = `${process.env.HOME}/Library/Application Support/Google/Chrome`;
const SCRAPING_DIR = `${process.env.HOME}/.cache/browser-tools`;
const CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function usage(code = 0) {
	console.log("Usage: browser-start.js [--profile [NAME]] [--list-profiles]");
	console.log("\nOptions:");
	console.log("  --profile [NAME]   Copy a Chrome profile (cookies, logins) and open it.");
	console.log('                     NAME is a profile\'s display name (e.g. "personal") or');
	console.log('                     its directory (e.g. "Profile 2"). Defaults to "Default".');
	console.log("  --list-profiles    List available Chrome profiles and exit.");
	process.exit(code);
}

// Map profile directory <-> display name via Chrome's Local State.
function readProfiles() {
	const localState = join(CHROME_DIR, "Local State");
	if (!existsSync(localState)) return [];
	try {
		const data = JSON.parse(readFileSync(localState, "utf8"));
		const cache = data?.profile?.info_cache ?? {};
		const lastUsed = data?.profile?.last_used;
		return Object.entries(cache).map(([dir, info]) => ({
			dir,
			name: info?.name ?? dir,
			lastUsed: dir === lastUsed,
		}));
	} catch {
		return [];
	}
}

// Resolve a user-supplied reference (display name or directory) to a directory.
function resolveProfileDir(ref) {
	if (!ref) return "Default";
	const profiles = readProfiles();
	const lc = ref.toLowerCase();
	const byDir = profiles.find((p) => p.dir.toLowerCase() === lc);
	if (byDir) return byDir.dir;
	const byName = profiles.find((p) => p.name.toLowerCase() === lc);
	if (byName) return byName.dir;
	// Fall back to an on-disk directory match if Local State is unreadable.
	if (existsSync(join(CHROME_DIR, ref))) return ref;
	console.error(`✗ No Chrome profile matching "${ref}".`);
	if (profiles.length) {
		console.error("Available profiles:");
		for (const p of profiles) console.error(`  ${p.dir}  —  ${p.name}`);
	}
	process.exit(1);
}

const args = process.argv.slice(2);

if (args.includes("--list-profiles")) {
	const profiles = readProfiles();
	if (!profiles.length) {
		console.log("No Chrome profiles found (is Chrome installed and run at least once?).");
		process.exit(0);
	}
	console.log("Available Chrome profiles:");
	for (const p of profiles) {
		console.log(`  ${p.dir.padEnd(12)} ${p.name}${p.lastUsed ? "  (last used)" : ""}`);
	}
	console.log('\nUse: browser-start.js --profile "<name or directory>"');
	process.exit(0);
}

let useProfile = false;
let profileDir = "Default";
for (let i = 0; i < args.length; i++) {
	const a = args[i];
	if (a === "--profile") {
		useProfile = true;
		const next = args[i + 1];
		if (next && !next.startsWith("--")) {
			profileDir = resolveProfileDir(next);
			i++;
		}
	} else if (a === "-h" || a === "--help") {
		usage(0);
	} else {
		console.log(`Unknown option: ${a}`);
		usage(1);
	}
}

// Check if already running on :9222
try {
	const browser = await puppeteer.connect({
		browserURL: "http://localhost:9222",
		defaultViewport: null,
	});
	await browser.disconnect();
	console.log("✓ Chrome already running on :9222");
	if (useProfile) console.log("  (To switch profiles, close that Chrome instance first.)");
	process.exit(0);
} catch {}

// Setup profile directory
execSync(`mkdir -p "${SCRAPING_DIR}"`, { stdio: "ignore" });

// Remove SingletonLock to allow new instance
try {
	execSync(`rm -f "${SCRAPING_DIR}/SingletonLock" "${SCRAPING_DIR}/SingletonSocket" "${SCRAPING_DIR}/SingletonCookie"`, { stdio: "ignore" });
} catch {}

if (useProfile) {
	if (!existsSync(join(CHROME_DIR, profileDir))) {
		console.error(`✗ Chrome profile directory not found: ${CHROME_DIR}/${profileDir}`);
		console.error("Run with --list-profiles to see available profiles.");
		process.exit(1);
	}
	console.log(`Syncing profile "${profileDir}"...`);
	// Copy the top-level Local State (profile metadata) and only the chosen
	// profile directory, so Chrome opens exactly that profile.
	if (existsSync(join(CHROME_DIR, "Local State"))) {
		execSync(`rsync -a "${CHROME_DIR}/Local State" "${SCRAPING_DIR}/Local State"`, { stdio: "pipe" });
	}
	execSync(
		`rsync -a --delete \
			--exclude='Sessions/' \
			--exclude='Current Session' \
			--exclude='Current Tabs' \
			--exclude='Last Session' \
			--exclude='Last Tabs' \
			"${CHROME_DIR}/${profileDir}/" "${SCRAPING_DIR}/${profileDir}/"`,
		{ stdio: "pipe" },
	);
}

// Start Chrome with flags to force new instance
const chromeArgs = [
	"--remote-debugging-port=9222",
	`--user-data-dir=${SCRAPING_DIR}`,
	"--no-first-run",
	"--no-default-browser-check",
];
if (useProfile) chromeArgs.push(`--profile-directory=${profileDir}`);

spawn(CHROME_BIN, chromeArgs, { detached: true, stdio: "ignore" }).unref();

// Wait for Chrome to be ready
let connected = false;
for (let i = 0; i < 30; i++) {
	try {
		const browser = await puppeteer.connect({
			browserURL: "http://localhost:9222",
			defaultViewport: null,
		});
		await browser.disconnect();
		connected = true;
		break;
	} catch {
		await new Promise((r) => setTimeout(r, 500));
	}
}

if (!connected) {
	console.error("✗ Failed to connect to Chrome");
	process.exit(1);
}

console.log(`✓ Chrome started on :9222${useProfile ? ` with profile "${profileDir}"` : ""}`);
