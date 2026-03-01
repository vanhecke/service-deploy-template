#!/usr/bin/env bash
# @description Declarative option parsing — define options once, get parsing and help for free.
#
# Usage:
#   source lib/core/options.sh
#   options::define "flag|h|help|Show usage help"
#   options::define "flag|v|verbose|Enable debug logging"
#   options::define "option|c|config|Configuration directory|etc"
#   options::parse "$@"
#
# Types:
#   flag   — boolean, sets variable to "true" when present (default: "false")
#   option — string value, requires an argument (default: 5th field or "")

[[ -n "${_OPTIONS_SH_LOADED:-}" ]] && return 0
readonly _OPTIONS_SH_LOADED=1

_OPTIONS_DEFS=()

# @description Register an option definition.
# @arg $1 string Pipe-delimited definition: type|short|long|description[|default]
options::define() {
    _OPTIONS_DEFS+=("$1")
}

# @description Convert a long option name to a variable name (dashes to underscores, uppercase).
# @arg $1 string Long option name (e.g. "dry-run")
_options::varname() {
    local name="$1"
    name="${name//-/_}"
    printf '%s' "${name^^}"
}

# @description Initialize all defined options to their default values.
_options::init_defaults() {
    local def type long default varname
    for def in "${_OPTIONS_DEFS[@]}"; do
        IFS='|' read -r type _ long _ default <<<"$def"
        varname="$(_options::varname "$long")"
        case "$type" in
            flag) printf -v "$varname" '%s' "false" ;;
            option) printf -v "$varname" '%s' "${default:-}" ;;
        esac
    done
}

# @description Print the Options: section of help text to stdout.
options::usage() {
    printf 'Options:\n'
    local def type short long desc default
    for def in "${_OPTIONS_DEFS[@]}"; do
        IFS='|' read -r type short long desc default <<<"$def"
        local flags
        flags="  -${short}, --${long}"
        if [[ "$type" == "option" ]]; then
            local placeholder="${long^^}"
            placeholder="${placeholder//-/_}"
            flags+=" <${placeholder}>"
        fi
        if [[ "$type" == "option" ]] && [[ -n "${default:-}" ]]; then
            printf '    %-28s %s (default: %s)\n' "$flags" "$desc" "$default"
        else
            printf '    %-28s %s\n' "$flags" "$desc"
        fi
    done
}

# @description Parse command-line arguments against defined options.
# @arg $@ Command-line arguments
options::parse() {
    _options::init_defaults
    ARGS=()

    while [[ $# -gt 0 ]]; do
        # Stop processing options after --
        if [[ "$1" == "--" ]]; then
            shift
            ARGS+=("$@")
            break
        fi

        # Collect positional arguments (non-option args)
        if [[ "$1" != -* ]]; then
            ARGS+=("$1")
            shift
            continue
        fi

        local matched=false
        local def type short long default varname
        for def in "${_OPTIONS_DEFS[@]}"; do
            IFS='|' read -r type short long _ default <<<"$def"
            varname="$(_options::varname "$long")"

            if [[ "$1" == "-${short}" ]] || [[ "$1" == "--${long}" ]]; then
                matched=true
                case "$type" in
                    flag)
                        if [[ "$long" == "help" ]]; then
                            if declare -F usage >/dev/null 2>&1; then
                                usage
                            else
                                options::usage
                            fi
                            exit 0
                        fi
                        printf -v "$varname" '%s' "true"
                        shift
                        ;;
                    option)
                        if [[ $# -lt 2 ]]; then
                            printf 'Error: --%s requires an argument\n' "$long" >&2
                            exit 1
                        fi
                        printf -v "$varname" '%s' "$2"
                        shift 2
                        ;;
                esac
                break
            fi
        done

        if [[ "$matched" == false ]]; then
            printf 'Error: unknown option: %s\n' "$1" >&2
            if declare -F usage >/dev/null 2>&1; then
                usage
            else
                options::usage
            fi
            exit 1
        fi
    done
}
