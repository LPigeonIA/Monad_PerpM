# Project Rules

## File Organization
1.  **Temporary Files**: All temporary files, logs, debug outputs, and generated test results MUST be placed in the `output/` directory.
    -   Use appropriate subdirectories (e.g., `output/logs/`, `output/data/`, `output/debug/`) to categorize them.
    -   Do NOT create temporary files in the root directory.

2.  **Service Management**:
    -   ALWAYS use `./quickstart.sh` to start or restart services.
    -   NEVER start services (keeper, indexer, etc.) individually unless strictly debugging a specific isolated component.
    -   `quickstart.sh` handles cleanup, build, and startup sequences automatically.

3.  **Documentation**:
    -   All documentation and markdown files (except `README.md`) MUST be placed in the `docs/` directory.

