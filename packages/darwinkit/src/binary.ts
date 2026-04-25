import { execSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  chmodSync,
  readFileSync,
  writeFileSync,
  rmSync,
  renameSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { createGunzip } from "node:zlib";
import { extract } from "tar";

const BINARY_NAME = "darwinkit";
const APP_BUNDLE_PATH = "DarwinKit.app/Contents/MacOS/darwinkit";
const CACHE_ROOT = join(homedir(), ".cache", "darwinkit");
// Cache lives at a stable path so macOS TCC doesn't treat each upgrade as a
// new app and re-prompt for Calendar/Reminders/Notifications permissions.
// Version tracking is moved to a sibling manifest file.
const CACHE_DIR = join(CACHE_ROOT, "latest");
const MANIFEST_PATH = join(CACHE_DIR, "version.json");
const REPO_URL = "https://github.com/genesiscz/darwinkit-swift.git";

interface CacheManifest {
  version: string;
}

/** Resolve the directory where this module lives (works in both ESM and CJS). */
function getPackageDir(): string {
  try {
    // ESM
    return dirname(fileURLToPath(import.meta.url));
  } catch {
    // CJS fallback
    return __dirname;
  }
}

let memoizedVersion: string | null = null;
function getPackageVersion(): string {
  if (memoizedVersion) return memoizedVersion;
  const pkgPath = join(getPackageDir(), "..", "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf-8")) as { version: string };
  memoizedVersion = pkg.version;
  return pkg.version;
}

function getReleaseURL(version: string): string {
  return `https://github.com/genesiscz/darwinkit-swift/releases/download/v${version}/darwinkit-macos-arm64.tar.gz`;
}

function readManifest(): CacheManifest | null {
  try {
    return JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as CacheManifest;
  } catch {
    return null;
  }
}

function writeManifest(version: string): void {
  writeFileSync(
    MANIFEST_PATH,
    JSON.stringify({ version }, null, 2) + "\n",
  );
}

export async function ensureBinary(binaryPath?: string): Promise<string> {
  // 1. Explicit path
  if (binaryPath) {
    if (!existsSync(binaryPath)) {
      throw new Error(`Binary not found at specified path: ${binaryPath}`);
    }
    return binaryPath;
  }

  // 2. Check bundled .app bundle (shipped with npm package, enables notifications)
  const bundledApp = join(getPackageDir(), "..", "bin", APP_BUNDLE_PATH);
  if (existsSync(bundledApp)) return bundledApp;

  // 3. Check bundled standalone binary
  const bundled = join(getPackageDir(), "..", "bin", BINARY_NAME);
  if (existsSync(bundled)) return bundled;

  // 4. Check PATH
  const fromPath = findOnPath(BINARY_NAME);
  if (fromPath) return fromPath;

  // 5. Use stable-path cache if its manifest matches the SDK version
  const expectedVersion = getPackageVersion();
  const manifest = readManifest();
  const cachedApp = join(CACHE_DIR, APP_BUNDLE_PATH);
  const cached = join(CACHE_DIR, BINARY_NAME);

  if (manifest?.version === expectedVersion) {
    if (existsSync(cachedApp)) return cachedApp;
    if (existsSync(cached)) return cached;
    // Manifest claims current but binary is missing — fall through to download.
  }

  // 6. Download and atomically replace the cache directory
  const releaseURL = getReleaseURL(expectedVersion);
  try {
    console.error(
      `[darwinkit] Downloading binary v${expectedVersion} from GitHub releases...`,
    );
    await downloadAndReplaceCache(releaseURL, expectedVersion);
    console.error("[darwinkit] Cached at", CACHE_DIR);
    if (existsSync(cachedApp)) return cachedApp;
    if (existsSync(cached)) {
      chmodSync(cached, 0o755);
      return cached;
    }
    throw new Error("Tarball did not contain expected binary or .app bundle");
  } catch (downloadError) {
    console.error("[darwinkit] Download failed:", downloadError);
  }

  // 7. Build from source as last resort
  if (findOnPath("swift")) {
    try {
      console.error("[darwinkit] Attempting to build from source...");
      mkdirSync(CACHE_DIR, { recursive: true });
      const built = await buildFromSource(cached);
      writeManifest(expectedVersion);
      return built;
    } catch (buildError) {
      console.error("[darwinkit] Build from source failed:", buildError);
    }
  }

  // 8. Fail with instructions
  throw new Error(
    "Could not find or install darwinkit binary.\n" +
      "Install it manually:\n" +
      `  curl -L ${releaseURL} | tar xz -C ~/.local/bin/\n` +
      "Or set the binary path:\n" +
      "  new DarwinKit({ binary: '/path/to/darwinkit' })",
  );
}

function findOnPath(name: string): string | null {
  try {
    return execSync(`which ${name}`, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    return null;
  }
}

async function downloadAndExtract(url: string, destDir: string): Promise<void> {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  if (!response.body) {
    throw new Error("No response body");
  }

  const nodeStream = Readable.fromWeb(response.body as any);
  await pipeline(nodeStream, createGunzip(), extract({ cwd: destDir }));
}

async function downloadAndReplaceCache(
  url: string,
  version: string,
): Promise<void> {
  // Download into a sibling staging dir so a failed/interrupted download
  // never corrupts the existing cache. Replace atomically (rmdir + rename).
  mkdirSync(CACHE_ROOT, { recursive: true });
  const stagingDir = join(
    CACHE_ROOT,
    `.staging-${process.pid}-${Date.now()}`,
  );
  mkdirSync(stagingDir, { recursive: true });
  try {
    await downloadAndExtract(url, stagingDir);
    writeFileSync(
      join(stagingDir, "version.json"),
      JSON.stringify({ version }, null, 2) + "\n",
    );
    if (existsSync(CACHE_DIR)) {
      rmSync(CACHE_DIR, { recursive: true, force: true });
    }
    renameSync(stagingDir, CACHE_DIR);
    const cachedBinary = join(CACHE_DIR, BINARY_NAME);
    if (existsSync(cachedBinary)) chmodSync(cachedBinary, 0o755);
    const cachedAppBinary = join(CACHE_DIR, APP_BUNDLE_PATH);
    if (existsSync(cachedAppBinary)) chmodSync(cachedAppBinary, 0o755);
  } catch (err) {
    rmSync(stagingDir, { recursive: true, force: true });
    throw err;
  }
}

async function buildFromSource(outputPath: string): Promise<string> {
  const { execSync } = await import("node:child_process");
  const tmpDir = execSync("mktemp -d", { encoding: "utf-8" }).trim();

  try {
    execSync(`git clone --depth 1 ${REPO_URL} "${tmpDir}/darwinkit-swift"`, {
      stdio: "pipe",
    });

    execSync("swift build -c release --arch arm64", {
      cwd: join(tmpDir, "darwinkit-swift", "packages", "darwinkit-swift"),
      stdio: "pipe",
      timeout: 300_000, // 5 min build timeout
    });

    const builtBinary = join(
      tmpDir,
      "darwinkit-swift",
      "packages",
      "darwinkit-swift",
      ".build",
      "arm64-apple-macosx",
      "release",
      "darwinkit",
    );
    const { copyFileSync } = await import("node:fs");
    copyFileSync(builtBinary, outputPath);
    chmodSync(outputPath, 0o755);
    console.error("[darwinkit] Built from source and cached at", outputPath);
    return outputPath;
  } finally {
    try {
      execSync(`rm -rf "${tmpDir}"`, { stdio: "pipe" });
    } catch {}
  }
}
