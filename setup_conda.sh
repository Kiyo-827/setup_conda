#!/usr/bin/env bash
# Usage: source ./setup_conda.sh environment.yml
# "bash ./setup_conda.sh environment.yml" activates only inside this script.
# modules.txt is overwritten beside the YAML file after a successful conda list.

_setup_conda_main() {
    local env_file conda_base conda_python env_name envs_json env_prefix
    local modules_file executed_at package_versions installer platform

    if [[ $# -ne 1 ]]; then
        printf 'Usage: source ./setup_conda.sh environment.yml\n' >&2
        return 1
    fi
    env_file=$1
    executed_at=$(date '+%Y-%m-%d %H:%M:%S %z') || return 1

    if ! command -v conda >/dev/null 2>&1; then
        printf 'conda was not found in PATH. Please install Miniconda.\n' >&2
        printf 'Official website: https://www.anaconda.com/docs/getting-started/installation\n' >&2
        printf 'Official downloads: https://repo.anaconda.com/miniconda/\n' >&2
        platform="$(uname -s)-$(uname -m)"
        case "$platform" in
            Linux-x86_64) installer=Miniconda3-latest-Linux-x86_64.sh ;;
            Linux-aarch64|Linux-arm64) installer=Miniconda3-latest-Linux-aarch64.sh ;;
            Darwin-arm64) installer=Miniconda3-latest-MacOSX-arm64.sh ;;
            *)
                printf 'Check the official website for an installer compatible with your OS / CPU (%s).\n' "$platform" >&2
                return 1
                ;;
        esac
        printf '\nDownload and installation example:\n' >&2
        printf '  wget https://repo.anaconda.com/miniconda/%s\n' "$installer" >&2
        printf '  bash %s\n' "$installer" >&2
        printf '\nAfter installation, open a new terminal and run this script again.\n' >&2
        printf 'If Miniconda is already installed, try: source ~/miniconda3/etc/profile.d/conda.sh\n' >&2
        return 1
    fi

    if [[ ! -f "$env_file" || ! -r "$env_file" ]]; then
        printf 'YAML file not found or not readable: %s\n' "$env_file" >&2
        return 1
    fi
    env_file="$(cd -- "$(dirname -- "$env_file")" && pwd)/$(basename -- "$env_file")"
    modules_file="$(dirname -- "$env_file")/modules.txt"

    conda_base=$(conda info --base) || return 1
    conda_python="$conda_base/bin/python"
    if [[ ! -x "$conda_python" ]]; then
        printf 'Conda Python executable not found: %s\n' "$conda_python" >&2
        return 1
    fi

    # Use conda's YAML dependency so quoted names, comments and CRLF are parsed correctly.
    env_name=$("$conda_python" - "$env_file" <<'PY'
import sys
from ruamel.yaml import YAML

try:
    with open(sys.argv[1], encoding="utf-8-sig") as stream:
        config = YAML(typ="safe").load(stream)
    if not isinstance(config, dict):
        raise ValueError("The YAML document must be a mapping with a top-level name: environment_name entry.")
    name = config.get("name")
    if not isinstance(name, str) or not name:
        raise ValueError("Specify the environment name as name: environment_name (envname: is not supported).")
    if name.startswith("-") or any(c.isspace() or c in '/\\:#' for c in name):
        raise ValueError("The environment name contains invalid characters.")
    if config.get("prefix"):
        raise ValueError("Remove prefix: and use name: to specify the environment for this script.")
    print(name)
except Exception as error:
    print(f"YAML error: {error}", file=sys.stderr)
    sys.exit(1)
PY
    ) || return 1

    envs_json=$(conda env list --json) || return 1
    env_prefix=$("$conda_python" -c '
import json
import os
import sys

name, base = sys.argv[1:]
for prefix in json.load(sys.stdin)["envs"]:
    is_base = os.path.normpath(prefix) == os.path.normpath(base)
    if (name == "base" and is_base) or (
        name != "base" and not is_base and os.path.basename(os.path.normpath(prefix)) == name
    ):
        print(prefix)
        break
' "$env_name" "$conda_base" <<< "$envs_json") || return 1

    if [[ -z "$env_prefix" ]]; then
        printf 'Creating environment "%s".\n' "$env_name"
        conda env create -f "$env_file" || return 1
        env_prefix=$env_name
    else
        printf 'Using existing environment "%s".\n' "$env_name"
    fi

    # Initialize activation in non-interactive Bash as well as when sourced.
    if [[ ! -r "$conda_base/etc/profile.d/conda.sh" ]]; then
        printf 'Conda initialization script not found or not readable.\n' >&2
        return 1
    fi
    source "$conda_base/etc/profile.d/conda.sh" || return 1
    conda activate "$env_prefix" || return 1

    # conda list includes pip-installed packages by default.
    # Capture first so a failed list command does not erase the previous report.
    package_versions=$(conda list) || return 1
    (
        set -o pipefail
        {
            printf 'Execution time: %s\n' "$executed_at"
            printf '%s\n' "$package_versions"
        } | tee "$modules_file"
    ) || return 1

    printf '\nPackage versions saved to: %s\n' "$modules_file"
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        printf 'To activate the environment in your current shell, run: source ./setup_conda.sh %q\n' "$env_file"
    fi
}

_setup_conda_main "$@"
