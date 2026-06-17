#!/usr/bin/env bash
# install-for-copilot-remote.sh
#
# Remote installer for GitHub Copilot skill setup.
# Designed to be run as:
#   curl -fsSL <raw-script-url> | bash
#
# What it does:
#   1. Downloads an agent-skills archive from GitHub
#   2. Copies skill directories to <target>/.github/skills/
#   3. Copies agent personas to <target>/.github/agents/ (renamed *.agent.md)
#   4. Creates <target>/.github/copilot-instructions.md (skipped if already exists)

set -euo pipefail

TARGET_DIR="$(pwd)"
SELECTED_SKILLS=""
INSTALL_AGENTS=true
INSTALL_INSTRUCTIONS=true
SOURCE_REPO="Karnonson/agent-skills"
SOURCE_REF="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills)
      SELECTED_SKILLS="$2"
      shift 2
      ;;
    --no-agents)
      INSTALL_AGENTS=false
      shift
      ;;
    --no-instructions)
      INSTALL_INSTRUCTIONS=false
      shift
      ;;
    --repo)
      SOURCE_REPO="$2"
      shift 2
      ;;
    --ref)
      SOURCE_REF="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  curl -fsSL <raw-script-url> | bash
  curl -fsSL <raw-script-url> | bash -s -- [TARGET_DIR] [options]

Options:
  --skills skill1,skill2,...   Comma-separated list of skills to install (default: all)
  --no-agents                  Skip copying agent personas
  --no-instructions            Skip creating copilot-instructions.md
  --repo owner/repo            Source repository (default: Karnonson/agent-skills)
  --ref branch-or-tag          Source git ref (default: main)
EOF
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "ERROR: target directory does not exist: ${TARGET_DIR}" >&2
  exit 1
fi
if [[ ! "${SOURCE_REPO}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: invalid --repo value '${SOURCE_REPO}' (expected owner/repo)" >&2
  exit 1
fi
if [[ ! "${SOURCE_REF}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: invalid --ref value '${SOURCE_REF}'" >&2
  exit 1
fi

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
GITHUB_DIR="${TARGET_DIR}/.github"
SKILLS_DEST="${GITHUB_DIR}/skills"
AGENTS_DEST="${GITHUB_DIR}/agents"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ARCHIVE_URL="https://codeload.github.com/${SOURCE_REPO}/tar.gz/${SOURCE_REF}"

echo "agent-skills → GitHub Copilot remote installer"
echo "Source repo : ${SOURCE_REPO}@${SOURCE_REF}"
echo "Target      : ${TARGET_DIR}"
echo ""

ARCHIVE_FILE="${TMP_DIR}/archive.tar.gz"
if ! curl -fsSL --connect-timeout 30 --max-time 300 -o "${ARCHIVE_FILE}" "${ARCHIVE_URL}"; then
  echo "ERROR: failed to download archive from ${ARCHIVE_URL}" >&2
  exit 1
fi
if ! tar -xzf "${ARCHIVE_FILE}" -C "${TMP_DIR}"; then
  echo "ERROR: failed to extract downloaded archive ${ARCHIVE_FILE}" >&2
  exit 1
fi

mapfile -t extracted_dirs < <(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | while read -r d; do basename "${d}"; done)
if [[ ${#extracted_dirs[@]} -ne 1 ]]; then
  echo "ERROR: expected one extracted top-level directory, found ${#extracted_dirs[@]}" >&2
  exit 1
fi
SRC_ROOT="${TMP_DIR}/${extracted_dirs[0]}"
if [[ ! -d "${SRC_ROOT}/skills" ]]; then
  echo "ERROR: downloaded archive missing skills directory" >&2
  exit 1
fi

mkdir -p "${SKILLS_DEST}"

if [[ -n "${SELECTED_SKILLS}" ]]; then
  IFS=',' read -ra skill_list <<< "${SELECTED_SKILLS}"
else
  mapfile -t skill_list < <(cd "${SRC_ROOT}/skills" && printf '%s\n' */ | sed 's:/$::')
fi

installed_skills=0
skipped_skills=0

for skill in "${skill_list[@]}"; do
  skill="$(echo "${skill}" | tr -d '[:space:]')"
  src="${SRC_ROOT}/skills/${skill}"
  if [[ ! -d "${src}" ]]; then
    echo "  WARN: skill '${skill}' not found — skipping" >&2
    skipped_skills=$((skipped_skills + 1))
    continue
  fi
  dest="${SKILLS_DEST}/${skill}"
  mkdir -p "${dest}"
  cp "${src}/SKILL.md" "${dest}/SKILL.md"
  if [[ -d "${src}/scripts" ]]; then
    cp -r "${src}/scripts" "${dest}/"
  fi
  echo "  ✓  skill: ${skill}"
  installed_skills=$((installed_skills + 1))
done

installed_agents=0
if [[ "${INSTALL_AGENTS}" == true && -d "${SRC_ROOT}/agents" ]]; then
  mkdir -p "${AGENTS_DEST}"
  for agent_file in "${SRC_ROOT}/agents/"*.md; do
    [[ -e "${agent_file}" ]] || continue
    base="$(basename "${agent_file}" .md)"
    cp "${agent_file}" "${AGENTS_DEST}/${base}.agent.md"
    echo "  ✓  agent: ${base}.agent.md"
    installed_agents=$((installed_agents + 1))
  done
fi

INSTRUCTIONS_FILE="${GITHUB_DIR}/copilot-instructions.md"
if [[ "${INSTALL_INSTRUCTIONS}" == true ]]; then
  if [[ -f "${INSTRUCTIONS_FILE}" ]]; then
    echo "  ⚠  ${INSTRUCTIONS_FILE} already exists — skipping (not overwritten)"
  else
    cat > "${INSTRUCTIONS_FILE}" <<'EOF'
# Project Coding Standards

## Testing
- Write tests before code (TDD)
- For bugs: write a failing test first, then fix (Prove-It pattern)
- Test hierarchy: unit > integration > e2e (use the lowest level that captures the behavior)
- Run `npm test` (or equivalent) after every change

## Code Quality
- Review across five axes: correctness, readability, architecture, security, performance
- Every PR must pass: lint, type check, tests, build
- No secrets in code or version control

## Implementation
- Build in small, verifiable increments
- Each increment: implement → test → verify → commit
- Never mix formatting changes with behavior changes

## Boundaries
- Always: Run tests before commits, validate user input
- Ask first: Database schema changes, new dependencies
- Never: Commit secrets, remove failing tests, skip verification
EOF
    echo "  ✓  created: .github/copilot-instructions.md"
  fi
fi

echo ""
echo "Done!"
echo "  Skills installed : ${installed_skills}"
if [[ ${skipped_skills} -gt 0 ]]; then
  echo "  Skills skipped   : ${skipped_skills}"
fi
if [[ "${INSTALL_AGENTS}" == true ]]; then
  echo "  Agents installed : ${installed_agents}"
fi
