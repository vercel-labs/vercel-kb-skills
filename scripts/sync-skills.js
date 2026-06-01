#!/usr/bin/env node

/**
 * @module sync-skills
 * @description Discovers skills in the skills/ directory and:
 *   1. Packages skills into downloadable `.skill` archives (zipped skill
 *      folders) under dist/, so people can grab a skill directly from a raw
 *      GitHub URL.
 *   2. Regenerates the "Available skills" table in README.md.
 *
 * Packaging is diff-aware: pass the directory names of the skills that changed
 * and only those archives are (re)built. A changed skill whose directory no
 * longer exists has its archive removed. With no arguments, every skill is
 * rebuilt and orphaned archives are pruned. The README is always regenerated
 * from the full set of current skills.
 *
 * Archives are written deterministically (no timestamps), so an unchanged
 * skill always produces byte-for-byte identical output.
 * @example
 * // Rebuild everything (from the repository root)
 * node scripts/sync-skills.js
 * @example
 * // Only repackage the named skills
 * node scripts/sync-skills.js tanstack-start-cloudflare-to-vercel
 */

import { mkdir, readdir, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateRawSync } from "node:zlib";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = join(__dirname, "..");
const SKILLS_DIR = join(ROOT_DIR, "skills");
const README_PATH = join(ROOT_DIR, "README.md");
const DIST_DIR = join(ROOT_DIR, "dist");

// Used to build the raw download URL for each packaged skill.
const REPO_SLUG = "vercel-labs/vercel-kb-skills";
const REPO_BRANCH = "main";

const FRONTMATTER_REGEX = /^---\n([\s\S]*?)\n---/;
const WHITESPACE_REGEX = /\S/;

function parseValue(raw) {
  const trimmed = raw.trim();
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return trimmed;
    }
  }
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseFrontmatter(content) {
  const match = content.match(FRONTMATTER_REGEX);
  if (!match) {
    return {};
  }

  const lines = match[1].split("\n");
  const result = {};
  let currentObject = null;

  for (const line of lines) {
    if (line.trim() === "") {
      continue;
    }

    const colonIndex = line.indexOf(":");
    if (colonIndex === -1) {
      continue;
    }

    const indent = line.search(WHITESPACE_REGEX);
    const key = line.slice(0, colonIndex).trim();
    const rawValue = line.slice(colonIndex + 1);

    if (indent > 0 && currentObject !== null) {
      const value = parseValue(rawValue);
      if (value !== "") {
        currentObject[key] = value;
      }
    } else {
      const value = parseValue(rawValue);
      if (value === "") {
        currentObject = {};
        result[key] = currentObject;
      } else {
        currentObject = null;
        result[key] = value;
      }
    }
  }

  return result;
}

// Recursively walks a directory and returns all file paths relative to it.
async function listFiles(dir) {
  const files = [];

  async function walk(current, prefix) {
    const entries = await readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        await walk(join(current, entry.name), relativePath);
      } else {
        files.push(relativePath);
      }
    }
  }

  await walk(dir, "");

  // SKILL.md first, then everything else alphabetically (stable ordering keeps
  // the generated archive deterministic).
  files.sort((a, b) => {
    if (a === "SKILL.md") {
      return -1;
    }
    if (b === "SKILL.md") {
      return 1;
    }
    return a.localeCompare(b);
  });

  return files;
}

// Scans the skills/ directory for subdirectories containing a SKILL.md,
// parses each file's frontmatter, and returns a sorted array of skill metadata.
async function discoverSkills() {
  const skills = [];

  let entries;
  try {
    entries = await readdir(SKILLS_DIR, { withFileTypes: true });
  } catch {
    console.warn("No skills directory found. Skipping sync.");
    return skills;
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    const skillDir = join(SKILLS_DIR, entry.name);
    const skillMdPath = join(skillDir, "SKILL.md");

    try {
      const skillMd = await readFile(skillMdPath, "utf-8");
      const frontmatter = parseFrontmatter(skillMd);
      const metadata = frontmatter.metadata || {};

      skills.push({
        dirName: entry.name,
        name: frontmatter.name || entry.name,
        description: frontmatter.description || "",
        oneLiner: metadata["one-liner"] || "",
        guide: metadata.guide || "",
      });
    } catch (error) {
      console.warn(
        `Warning: Could not read skill at ${entry.name}:`,
        error.message
      );
    }
  }

  return skills.sort((a, b) => a.dirName.localeCompare(b.dirName));
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xed_b8_83_20 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let crc = 0xff_ff_ff_ff;
  for (let i = 0; i < buffer.length; i++) {
    crc = CRC_TABLE[(crc ^ buffer[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xff_ff_ff_ff) >>> 0;
}

// Builds a minimal ZIP archive (DEFLATE compressed, no timestamps) from a list
// of { name, data } entries. Deterministic output for the same inputs.
function createZip(entries) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBuffer = Buffer.from(entry.name, "utf-8");
    const crc = crc32(entry.data);
    const compressed = deflateRawSync(entry.data, { level: 9 });

    const localHeader = Buffer.alloc(30);
    localHeader.writeUInt32LE(0x04_03_4b_50, 0); // local file header signature
    localHeader.writeUInt16LE(20, 4); // version needed to extract
    localHeader.writeUInt16LE(0, 6); // general purpose bit flag
    localHeader.writeUInt16LE(8, 8); // compression method: deflate
    localHeader.writeUInt16LE(0, 10); // last mod file time
    localHeader.writeUInt16LE(0, 12); // last mod file date
    localHeader.writeUInt32LE(crc, 14); // crc-32
    localHeader.writeUInt32LE(compressed.length, 18); // compressed size
    localHeader.writeUInt32LE(entry.data.length, 22); // uncompressed size
    localHeader.writeUInt16LE(nameBuffer.length, 26); // file name length
    localHeader.writeUInt16LE(0, 28); // extra field length

    localParts.push(localHeader, nameBuffer, compressed);

    const centralHeader = Buffer.alloc(46);
    centralHeader.writeUInt32LE(0x02_01_4b_50, 0); // central dir header signature
    centralHeader.writeUInt16LE(20, 4); // version made by
    centralHeader.writeUInt16LE(20, 6); // version needed to extract
    centralHeader.writeUInt16LE(0, 8); // general purpose bit flag
    centralHeader.writeUInt16LE(8, 10); // compression method
    centralHeader.writeUInt16LE(0, 12); // last mod file time
    centralHeader.writeUInt16LE(0, 14); // last mod file date
    centralHeader.writeUInt32LE(crc, 16); // crc-32
    centralHeader.writeUInt32LE(compressed.length, 20); // compressed size
    centralHeader.writeUInt32LE(entry.data.length, 24); // uncompressed size
    centralHeader.writeUInt16LE(nameBuffer.length, 28); // file name length
    centralHeader.writeUInt16LE(0, 30); // extra field length
    centralHeader.writeUInt16LE(0, 32); // file comment length
    centralHeader.writeUInt16LE(0, 34); // disk number start
    centralHeader.writeUInt16LE(0, 36); // internal file attributes
    centralHeader.writeUInt32LE(0, 38); // external file attributes
    centralHeader.writeUInt32LE(offset, 42); // relative offset of local header

    centralParts.push(centralHeader, nameBuffer);

    offset += localHeader.length + nameBuffer.length + compressed.length;
  }

  const centralDirectory = Buffer.concat(centralParts);
  const localData = Buffer.concat(localParts);

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06_05_4b_50, 0); // end of central dir signature
  eocd.writeUInt16LE(0, 4); // number of this disk
  eocd.writeUInt16LE(0, 6); // disk with start of central directory
  eocd.writeUInt16LE(entries.length, 8); // central dir records on this disk
  eocd.writeUInt16LE(entries.length, 10); // total central dir records
  eocd.writeUInt32LE(centralDirectory.length, 12); // size of central directory
  eocd.writeUInt32LE(localData.length, 16); // offset of central directory
  eocd.writeUInt16LE(0, 20); // comment length

  return Buffer.concat([localData, centralDirectory, eocd]);
}

// Packages a single skill into dist/<dirName>.skill. The archive contains the
// skill's files at its root (SKILL.md and everything else), so unzipping yields
// the skill's contents directly.
async function packageSkill(skill) {
  const skillDir = join(SKILLS_DIR, skill.dirName);
  const files = await listFiles(skillDir);

  const entries = await Promise.all(
    files.map(async (file) => ({
      name: file,
      data: await readFile(join(skillDir, file)),
    }))
  );

  const archive = createZip(entries);
  const archiveName = `${skill.dirName}.skill`;
  await writeFile(join(DIST_DIR, archiveName), archive);
  console.log(`Packaged ${archiveName} (${files.length} files)`);
}

// Removes dist/<dirName>.skill if it exists (used when a skill is deleted).
async function removeArchive(dirName) {
  try {
    await unlink(join(DIST_DIR, `${dirName}.skill`));
    console.log(`Removed ${dirName}.skill (skill no longer exists)`);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

// Deletes any dist/*.skill that doesn't correspond to a current skill.
async function pruneOrphans(skills) {
  const valid = new Set(skills.map((skill) => `${skill.dirName}.skill`));

  let entries;
  try {
    entries = await readdir(DIST_DIR, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (entry.isFile() && entry.name.endsWith(".skill") && !valid.has(entry.name)) {
      await unlink(join(DIST_DIR, entry.name));
      console.log(`Removed orphan ${entry.name}`);
    }
  }
}

function escapeCell(value) {
  return value.replace(/\|/g, "\\|");
}

// Builds the markdown "Available skills" table, including a raw GitHub
// download link to each packaged .skill archive.
function generateReadmeSkillsTable(skills) {
  if (skills.length === 0) {
    return "\n*No skills available yet.*\n";
  }

  const lines = [
    "",
    "| Skill | What it does | Companion guide | Download |",
    "| --- | --- | --- | --- |",
  ];

  for (const skill of skills) {
    const skillCell = `[\`${skill.dirName}\`](./skills/${skill.dirName})`;
    const whatCell = escapeCell(skill.oneLiner || skill.description);
    const guideCell = skill.guide
      ? `[Read the guide](${skill.guide})`
      : "—";
    const downloadUrl = `https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_BRANCH}/dist/${skill.dirName}.skill`;
    const downloadCell = `[\`${skill.dirName}.skill\`](${downloadUrl})`;

    lines.push(
      `| ${skillCell} | ${whatCell} | ${guideCell} | ${downloadCell} |`
    );
  }

  lines.push("");
  return lines.join("\n");
}

// Replaces the skills table between the START/END markers in README.md
// with a freshly generated table from the current skills list.
async function updateReadme(skills) {
  const content = await readFile(README_PATH, "utf-8");
  const startMarker = "<!-- START:Available-Skills -->";
  const endMarker = "<!-- END:Available-Skills -->";

  const startIndex = content.indexOf(startMarker);
  const endIndex = content.indexOf(endMarker);

  if (startIndex === -1 || endIndex === -1) {
    console.warn("Warning: Could not find skill markers in README.md");
    return false;
  }

  const table = generateReadmeSkillsTable(skills);
  const newContent =
    content.slice(0, startIndex + startMarker.length) +
    table +
    content.slice(endIndex);

  await writeFile(README_PATH, newContent, "utf-8");
  return true;
}

// Entry point — packages the requested (or all) skills, then regenerates the
// README from the full set of current skills.
async function main() {
  const changed = process.argv.slice(2).filter(Boolean);
  console.log("Syncing agent skill(s)...\n");

  const skills = await discoverSkills();
  const skillByDir = new Map(skills.map((skill) => [skill.dirName, skill]));

  await mkdir(DIST_DIR, { recursive: true });

  if (changed.length > 0) {
    console.log(`Packaging ${changed.length} changed skill(s):`);
    for (const dirName of changed) {
      const skill = skillByDir.get(dirName);
      if (skill) {
        await packageSkill(skill);
      } else {
        await removeArchive(dirName);
      }
    }
  } else {
    console.log(`Packaging all ${skills.length} skill(s):`);
    for (const skill of skills) {
      await packageSkill(skill);
    }
    await pruneOrphans(skills);
  }
  console.log();

  const readmeUpdated = await updateReadme(skills);
  if (readmeUpdated) {
    console.log("Updated README.md");
  }

  console.log("\nSkill sync complete!");
}

main().catch((error) => {
  console.error("Error:", error.message);
  process.exit(1);
});
