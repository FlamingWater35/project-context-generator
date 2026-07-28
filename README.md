# Project Context Generator

A high-performance desktop application for generating structured, token-optimized context prompts from project repositories for Large Language Models (LLMs) and AI Agents.

---

## Features

### 📁 Project Management & Persistence

- **Multiple Project Profiles** – Create, rename, delete, and switch between project configurations with dedicated root folders and ignore rules.
- **Search & Sort** – Dynamically filter projects by name and sort profiles alphabetically (A–Z, Z–A) or by creation date (newest/oldest first).
- **Workspace State Persistence** – Automatically saves and restores your last opened project, window position/size, sidebar layout width, and file selections across sessions.

### 🧠 AI Agent Skills Integration

- **Auto-Detection** – Automatically scans your codebase for agent skill definition files (e.g., `SKILL.md`, `skills.md`, `.prompt.md`, `.cursor/rules/`, `.windsurfrules`).
- **Reference File Parsing** – Automatically discovers and embeds skill reference documents located within skill directories.
- **Custom Skills** – Define custom, user-level AI agent skills and prompt guidance directly in the UI.

### 🛡️ Smart Ignore Patterns

- **Flexible Wildcard Globs** – `.gitignore`-style glob pattern matching (e.g., `node_modules/**`, `*.log`, `build/**`, `.env.*`).
- **One-Click Presets** – Quickly toggle common exclusion presets (`.git`, `node_modules`, `dist`, `.dart_tool`, `coverage`, `__pycache__`, etc.).
- **Contextual Ignore Menu** – Right-click or use the action menu on any file or folder to ignore specific files, entire subdirectories, or all files sharing the same extension.

### ⚙️ Multi-Select & Batch Operations

- **Batch Highlights** – Long-press or click the highlight toggle to multi-select files and folders across the tree.
- **Batch Folder Actions** – Contained file selection controls per directory (Select All, Deselect All, Invert Selection).
- **Batch Operations Toolbar** – Easily check, uncheck, or ignore all highlighted items at once.

### 🔄 Change Detection & Snapshots

- **Automatic Snapshot Tracking** – Compares physical disk assets against saved project snapshots.
- **"NEW" Visual Badges** – Highlights newly added files on disk since your last check or snapshot update.
- **Conflict Resolution** – Prompts you to refresh your snapshot or copy the existing state when disk changes are detected during generation.

### 📊 Live Status Bar

- **Real-time metrics displaying:**
  - Total included file count
  - Active skill count
  - Total output line count
  - Uncompressed character size (B, KB, MB)
  - Estimated LLM token count (~4 characters per token heuristic)

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Ctrl + G` / `Cmd + G` | Generate context prompt and copy directly to clipboard |
| `Right-Click` on tree item | Open granular ignore options menu |
| `Long-Press` on tree item | Toggle multi-selection highlight state |

---

## Usage Guide

1. **Create a Project Configuration** – Click the `+` icon in the sidebar to create a new profile.
2. **Select Root Directory** – Click **Select Root Folder** to point to your repository.
3. **Configure Exclusions** – Click **Ignores** to adjust wildcard rules or toggle common environment presets.
4. **Select Files & Skills** –
   - Check individual files or use folder actions (**Select All**, **Invert**) to include source files.
   - Click **Skills** to select auto-detected AI Agent instructions or define custom skills.
5. **Check for Disk Changes** – Click **Check for Changes** to update snapshot tracking and mark newly added files with **NEW** badges.
6. **Generate & Copy** – Click **Generate & Copy** (or press `Ctrl+G` / `Cmd+G`) to build the context prompt and copy it directly to your system clipboard.

---

## Generated Prompt Format

```text
--- PROJECT CONTEXT: My Project ---
File Tree Structure:
├── src/
│   ├── main.dart [selected]
│   └── utils.dart [selected]
└── README.md [selected]

--- MAIN FILE(S) CONTENT ---
--- File: src/main.dart ---
void main() {
  print('Hello World');
}
--- End File ---

--- File: src/utils.dart ---
String formatText(String input) => input.trim();
--- End File ---

--- AGENT SKILLS ---
--- Skill: Code Reviewer ---
Description: Guidelines for PR reviews and code quality
Always ensure functions have explicit return types and error handling.
--- End Skill ---
```
