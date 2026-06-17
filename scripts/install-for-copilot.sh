#!/usr/bin/env bash
# install-for-copilot.sh
#
# Installs agent-skills into a target repository for use with GitHub Copilot.
#
# What it does:
#   1. Copies every skill directory to <target>/.github/skills/
#   2. Copies every agent persona to <target>/.github/agents/ (renamed *.agent.md)
#   3. Creates <target>/.github/copilot-instructions.md (skipped if already exists)
#
# Usage:
#   bash scripts/install-for-copilot.sh [TARGET_DIR] [--skills skill1,skill2,...] [--no-agents] [--no-instructions]
#
# Arguments:
#   TARGET_DIR              Path to the repository to install into (default: current directory)
#   --skills skill1,...     Comma-separated list of skills to install (default: all)
#   --no-agents             Skip copying agent personas
#   --no-instructions       Skip creating copilot-instructions.md
#
# Examples:
#   # Install everything into the current repo
#   bash scripts/install-for-copilot.sh
#
#   # Install into a specific repo
#   bash scripts/install-for-copilot.sh ~/projects/my-app
#
#   # Install only two skills, no agents
#   bash scripts/install-for-copilot.sh ~/projects/my-app --skills test-driven-development,code-review-and-quality --no-agents

set -euo pipefail

# ── Locate this script's repository root ─────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_SRC="${REPO_ROOT}/skills"
AGENTS_SRC="${REPO_ROOT}/agents"

# ── Defaults ──────────────────────────────────────────────────────────────────
TARGET_DIR="$(pwd)"
SELECTED_SKILLS=""   # empty = all
INSTALL_AGENTS=true
INSTALL_INSTRUCTIONS=true

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills)
      if [[ $# -lt 2 || "${2:-}" == -* ]]; then
        echo "ERROR: --skills requires a comma-separated value" >&2
        exit 1
      fi
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
    -h|--help)
      cat <<'EOF'
install-for-copilot.sh

Installs agent-skills into a target repository for use with GitHub Copilot.

Usage:
  bash scripts/install-for-copilot.sh [TARGET_DIR] [--skills skill1,skill2,...] [--no-agents] [--no-instructions]

Arguments:
  TARGET_DIR              Path to the repository to install into (default: current directory)
  --skills skill1,...     Comma-separated list of skills to install (default: all)
  --no-agents             Skip copying agent personas
  --no-instructions       Skip creating copilot-instructions.md
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

# ── Validate ──────────────────────────────────────────────────────────────────
if [[ ! -d "${SKILLS_SRC}" ]]; then
  echo "ERROR: skills directory not found at ${SKILLS_SRC}" >&2
  exit 1
fi
if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "ERROR: target directory does not exist: ${TARGET_DIR}" >&2
  exit 1
fi

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
GITHUB_DIR="${TARGET_DIR}/.github"
SKILLS_DEST="${GITHUB_DIR}/skills"
AGENTS_DEST="${GITHUB_DIR}/agents"

echo "agent-skills → GitHub Copilot installer"
echo "Source : ${REPO_ROOT}"
echo "Target : ${TARGET_DIR}"
echo ""

# ── Install skills ────────────────────────────────────────────────────────────
mkdir -p "${SKILLS_DEST}"

# Determine which skills to install
if [[ -n "${SELECTED_SKILLS}" ]]; then
  IFS=',' read -ra skill_list <<< "${SELECTED_SKILLS}"
else
  mapfile -t skill_list < <(find "${SKILLS_SRC}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
fi

installed_skills=0
skipped_skills=0

for skill in "${skill_list[@]}"; do
  skill="$(echo "${skill}" | tr -d '[:space:]')"
  src="${SKILLS_SRC}/${skill}"
  if [[ ! -d "${src}" ]]; then
    echo "  WARN: skill '${skill}' not found in ${SKILLS_SRC} — skipping" >&2
    skipped_skills=$((skipped_skills + 1))
    continue
  fi
  dest="${SKILLS_DEST}/${skill}"
  mkdir -p "${dest}"
  cp "${src}/SKILL.md" "${dest}/SKILL.md"
  # Copy scripts/ subdirectory if present
  if [[ -d "${src}/scripts" ]]; then
    cp -r "${src}/scripts" "${dest}/"
  fi
  echo "  ✓  skill: ${skill}"
  installed_skills=$((installed_skills + 1))
done

# ── Install agent personas ────────────────────────────────────────────────────
installed_agents=0

if [[ "${INSTALL_AGENTS}" == true && -d "${AGENTS_SRC}" ]]; then
  mkdir -p "${AGENTS_DEST}"
  for agent_file in "${AGENTS_SRC}"/*.md; do
    [[ -e "${agent_file}" ]] || continue
    base="$(basename "${agent_file}" .md)"
    dest_file="${AGENTS_DEST}/${base}.agent.md"
    cp "${agent_file}" "${dest_file}"
    echo "  ✓  agent: ${base}.agent.md"
    installed_agents=$((installed_agents + 1))
  done
fi

# ── Create copilot-instructions.md ───────────────────────────────────────────
INSTRUCTIONS_FILE="${GITHUB_DIR}/copilot-instructions.md"
created_instructions=false

if [[ "${INSTALL_INSTRUCTIONS}" == true ]]; then
  if [[ -f "${INSTRUCTIONS_FILE}" ]]; then
    echo ""
    echo "  ⚠  ${INSTRUCTIONS_FILE} already exists — skipping (not overwritten)"
  else
    cat > "${INSTRUCTIONS_FILE}" << 'EOF'
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
    chmod 644 "${INSTRUCTIONS_FILE}"
    echo "  ✓  created: .github/copilot-instructions.md"
    created_instructions=true
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Done!"
echo "  Skills installed : ${installed_skills}"
if [[ ${skipped_skills} -gt 0 ]]; then
  echo "  Skills skipped   : ${skipped_skills}"
fi
if [[ "${INSTALL_AGENTS}" == true ]]; then
  echo "  Agents installed : ${installed_agents}"
fi
echo ""
echo "Next steps:"
if [[ "${INSTALL_INSTRUCTIONS}" == true ]]; then
  if [[ "${created_instructions}" == true ]]; then
    echo "  1. Review .github/copilot-instructions.md and tailor it to your project"
  else
    echo "  1. Keep your existing .github/copilot-instructions.md or update it as needed"
  fi
  echo "  2. Commit the .github/ additions to your repository"
  echo "  3. In Copilot Chat, agents are available as @<name> (e.g. @code-reviewer)"
else
  echo "  1. Commit the .github/ additions to your repository"
  echo "  2. In Copilot Chat, agents are available as @<name> (e.g. @code-reviewer)"
fi
