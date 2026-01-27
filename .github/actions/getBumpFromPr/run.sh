#!/bin/bash

debug() {
    printf "$@" >&2
}

parseBumpLine() {
    # Parses the semver bump line and prints the bump type as
    # 'MAJOR', 'MINOR' or 'PATCH'
    local pattern='^[[:space:]]*-[[:space:]]+\[x][[:space:]]+(Major|Minor|Patch)[[:space:]]*$'
    if [[ "$1" =~ ${pattern} ]]; then
        local bumpVer="${BASH_REMATCH[1]}"
        local capsCaseBumpVer=$(printf '%s\n' "${bumpVer}" | tr '[:lower:]' '[:upper:]')
        printf '%s\n' "${capsCaseBumpVer}"
    else
        return 1
    fi
}

findBumpLine() {
    local count=0
    local bumpType
    while read -r line; do
        local out 
        if out=$(parseBumpLine "${line}"); then
            bumpType="${out}"
            count=$(expr "${count}" + 1)
        fi
    done <<< "$1"
    if [ "${count}" -gt 1 ]; then
        debug "Multiple bump versions checked - only one allowed\n"
        return 1
    elif [ "${count}" -eq 0 ]; then
        debug "No bump version checked - need exactly one\n"
        return 1
    fi

    printf "%s\n" "${bumpType}"
}

if [ out=$(findBumpLine "$1") ]; then
    printf "bump-type=%s\n" "${out}" >> "${GITHUB_OUTPUT}"
else
    exit 1
fi