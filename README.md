# Project Context Generator

A desktop application for generating structured context prompts from project files.

---

## Features

- **Project Configurations** – Save multiple project setups with different root folders and ignore patterns
- **File Tree** – Browse the directory structure with visual indicators for newly added files
- **Ignore Patterns** – Flexible `.gitignore`-style patterns to exclude files (e.g., `node_modules/**`, `*.log`, `.git/**`)
- **Change Detection** – Automatically detects new files since your last check and marks them with "NEW" labels
- **One-Click Export** – Generates a formatted prompt including file tree structure and file contents, copied directly to clipboard
- **Persistent State** – Remembers your selections and snapshots between sessions

---

## Usage

1. **Create a Project** – Click the `+` button in the sidebar to create a new project config
2. **Select Root Folder** – Choose the directory containing your project files
3. **Configure Ignores** – Click the "Ignores" button to set up exclusion patterns (defaults provided for common directories like `.git`, `node_modules`, `build`)
4. **Select Files** – Check the files you want to include in the context (use the folder actions to select/deselect recursively)
5. **Check for Changes** – Click "Check for Changes" to scan for new files
6. **Generate** – Click "Generate & Copy" to create the context prompt.

---

## Generated Output Format

```text
--- PROJECT CONTEXT: My Project ---
File Tree Structure:
├── src/
│   ├── main.dart
│   └── utils.dart
└── README.md
--- MAIN FILE(S) CONTENT ---
--- File: src/main.dart ---
[file content here]
--- End File ---
--- File: src/utils.dart ---
[file content here]
--- End File ---
```
