#!/bin/bash

debug() {
    # shellcheck disable=SC2059
    printf "$@" >&2
}

parseSemanticVersion() {
    # Prints the MAJOR MINOR and PATCH integers of a semver specification
    # separated by space characters on one line
    # Semantic Versions should be prefixed with a 'v', e.g. 'v1.2.3'
    #
    # Returns an exit code of 0 if the given string is a valid semver
    # and 1 if it is not.

    # Lifted from the recommended regex specified at
    # https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
    # Validated using test group from semver.org
    # https://regex101.com/r/mpLfin/1
    # Non-capturing groups and shorthand character classes are not supported by
    # Bash so these have been substituted for POSIX character classes and
    # capturing groups.  In effect, '\d' -> '[[:digit:]]' & '(:?.*)' -> '(.*)'
    # Also added a literal 'v' prefix
    local pattern='^v(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)(-((0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'

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
    local tags
    tags=$(git tag --points-at "${sha}~1")
    for tag in ${tags}; do
        if parseSemanticVersion "${tag}" >/dev/null; then
            printf "%s\n" "${tag}"
            return 0
        fi
    done
    # No match found
    return 1
}

isBumpType() {
    # Checks to see if its argument is a valid semantic versioning bump type
    # i.e. one of 'MAJOR', 'MINOR', or 'PATCH'
    # Returns a successful exit status if so, and an error exit status if not
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
    # Increments a semantic version string based on the given bump type.
    # The semantic version string should be prefixed with 'v'
    # Example
    # > incrementSemVer "MAJOR" "v1.2.3"
    #   v2.0.0

    # Validate args
    if [ $# != 2 ]; then
        debug "Usage: $0 <MAJOR|MINOR|PATCH> <semver>\n"
        return 1
    fi
    local bumpType="$1"
    local semver="$2"
    isBumpType "${bumpType}" || return 1

    # Parse out the major, minor, patch versions from the semver string
    if out=$(parseSemanticVersion "${semver}"); then
        local major minor patch
        IFS=' ' read -r major minor patch <<< "${out}"
    else
        debug "Could not parse '%s' as a semver\n" "${semver}"
        return 1
    fi

    # Increment correct version
    case "${bumpType}" in
        MAJOR)
            major=$((major+1))
            minor=0
            patch=0
            ;;
        MINOR)
            minor=$((minor+1))
            patch=0
            ;;
        PATCH)
            patch=$((patch+1))
            ;;
    esac
    printf "v%d.%d.%d\n" "${major}" "${minor}" "${patch}"
}

tagSha() {
    # Given a tag string and a git commit SHA, tags that commit and pushes it
    # to the remote origin
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
    # Given a semantic versioning bump type and a git commit SHA,
    # Looks at the previous commit from that SHA for any tags in
    # the form a semantic versioning string (e.g. 'v1.2.3').
    # It then increments that semantic version according to the
    # given bump type and tags the given commit SHA with the incremented
    # semantic version string.
    local bumpType="$1"
    isBumpType "${bumpType}" || return 1
    local sha="$2"

    local lastTag
    if ! lastTag=$(getLastSemverTag "${sha}"); then
        debug "Could not find semver tag on last commit\n"
        return 1
    fi
    local nextTag
    if ! nextTag=$(incrementSemVer "${bumpType}" "${lastTag}"); then
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
if ! incrementAndTag "$1" "$2"; then
    exit 1;
fi
