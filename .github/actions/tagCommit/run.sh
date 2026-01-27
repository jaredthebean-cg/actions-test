#!/bin/bash
set -o xtrace
debug() {
    printf "$@"
}

parseSemanticVersion() {
    # Prints the MAJOR MINOR and PATCH integers of a semver specification
    # separated by space characters on one line
    #
    # Returns an exit code of 0 if the given string is a valid semver
    # and 1 if it is not.

    # Lifted from the recommended regex specified at
    # https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
    # Non-capturing groups and shorthand character classes are not supported by
    # Bash so these have been substituted for POSIX character classes and
    # capturing groups.  In effect, '\d' -> '[[:digit:]]' & '(:?.*)' -> '(.*)'
    local pattern='^(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)(-((0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][[:digit:]]*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'

    if [[ "$1" =~ ${pattern} ]]; then
        printf "%u %u %u\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    else
        return 1
    fi
}

getLastSemverTag() {
    # Prints the first tag listed that points to the last commit that is a
    # semver.
    #
    # Returns an exit code of 0 if a semver tag is found
    # and 1 if none point to the last commit.
    local sha="$1"
    local tags=$(git tag --points-at "${sha}~1")
    for tag in ${tags}; do
        if parseSemanticVersion "${tag}" >/dev/null; then
            printf "%s\n" "${tag}"
            return 0 
        fi
    done
    # No match found
    return 1
}

checkVersionType() {
    case "${1}" in
        # pass as this is the good condition
        MAJOR|MINOR|PATCH) 
            return 0
            ;; 
        # error condition
        *)
            debug "Invalid version type '%s' not one of 'MAJOR|MINOR|PATCH'\n" "${1}"
            return 1
            ;;
    esac
}

incrementSemVer() {
    # Validate args
    if [ $# != 2 ]; then
        debug "Usage: $0 <MAJOR|MINOR|PATCH> <semver>\n"
        return 1
    fi
    local versionType="$1"
    local semver="$2"
    checkVersionType "${versionType}" || return 1

    # Parse out the major, minor, patch versions from the semver string
    if out=$(parseSemanticVersion "${semver}"); then
        local major minor patch
        IFS=' ' read major minor patch <<< ${out}
    else
        debug "Could not parse '%s' as a semver\n" "${semver}"
        return 1
    fi

    # Increment correct version
    case "${versionType}" in
        MAJOR)
            major=$(expr ${major} + 1)
            ;;
        MINOR)
            minor=$(expr ${minor} + 1)
            ;;
        PATCH)
            patch=$(expr ${patch} + 1)
            ;;
    esac
    printf "%d.%d.%d\n" ${major} ${minor} ${patch}
}

tagSha() {
    if ! git tag "$1" "$2"; then
        debug "Could not tag commit\n"
        return 1
    fi
    if ! git push origin "$1"; then
        debug "Could not push tag to origin\n"
        return 1
    fi
}

incrementAndTag() {
    local versionType="$1"
    checkVersionType "${versionType}" || return 1
    local sha="$2"

    local lastTag
    if ! lastTag=$(getLastSemverTag "${sha}"); then
        debug "Could not find semver tag on last commit\n"
        return 1
    fi
    local nextTag
    if ! nextTag=$(incrementSemVer "${versionType}" "${lastTag}"); then
        debug "Could not increment '%s'\n"  "${lastTag}"
        return 1;
    fi
    if ! tagSha "${nextTag}" "${sha}"; then
        debug "Could not tag sha\n"
        return 1;
    fi
    printf "%s %s\n" "${nextTag}" "${sha}"
}

################################################################################
#                                 Main Script                                  #
################################################################################

# Make the our git workspace a safe directory so git doesn't
# complain about different ownership (as we are running as 'root' in Docker)
git config --global --add safe.directory /github/workspace
# Checkout action fetch-tags seems broken so we ensure they're fetched
git fetch --tags
incrementAndTag "$1" "$2"