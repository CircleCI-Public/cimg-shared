#!/usr/bin/env bash
# extglob is enabled for extended and advanced globbing, which is needed for the OpenJDK images
shopt -s extglob

vers=()

###
  # the next three functions work as the version string parsers and are what decides which versions go into the vers array
  # versionEqual checks for equality; in which case the version is skipped because it is considered up to date
  # versionGTE checks if the version is greater, in which case we use that value
  # newVers is a result of if a given directory, dated or by major.minor, exists; if is does, then we check the version currently
  # inside the Dockerfile, otherwise, we know the version being passed is new because it is not being tracked
###

versionEqual() {
  newVersion=$1
  currentVersion=$2

  if [ "$newVersion" = "$currentVersion" ]; then
    echo "Current version $currentVersion matches $newVersion. Does not need an update"
    return 1
  else
    versionGreaterThan "$newVersion" "$currentVersion"
  fi
}

versionGreaterThan() {
  if [ "$(printf '%s\n' "$newVersion" "$currentVersion" | sort -V | head -n1)" = "$currentVersion" ]; then
    echo "Parsed version $newVersion is greater than $currentVersion"
    return 0
  else
    echo "Parsed version $newVersion is not greater than $currentVersion"
    return 1
  fi
}

###
  # directory check is  a helper function to check the given directory in order to call newVers or not; it is enabled
  # by the "searchTerm" variable, which is nested within each "get" function in order to determine the currentVersion we are
  # comparing the newVersion to
###

directoryCheck() {
  local directory=$1
  local searchTerm=$2

  if [ -d "$directory" ]; then
    currentVersion=$searchTerm
    echo "directory $directory exists; checking for matching versions: $currentVersion"
    versionEqual "$newVersion" "$currentVersion"
  else
    generateVersionString "$newVersion" "$builtParam"
  fi
}

generateVersions () {
  local dirtyVersion=$1
  local cut=$2

  if [[ -n $cut ]]; then
    newVersion=${cut}
  else
    newVersion=${dirtyVersion}
  fi

  if [[ $newVersion =~ ([0-9]+\.[0-9]+\.[0-9]) ]]; then
    majorMinor=${newVersion%.*}
  else
    majorMinor=${newVersion}
  fi

  if [[ $majorMinor =~ ([0-9]+\.[0-9]+\.[0-9]) ]]; then
    majorMinor=${majorMinor%.*}
  fi
}

generateVersionString() {
  local version=$1

  if [ -n "$builtParam" ]; then
    versionString=${version}${builtParam}
  else
    versionString=${version}
  fi

  vers+=( "$versionString" )
}

generateSearchTerms () {
  local searchFor=$1
  local searchFile=$2
  local trimCharacters=$3

  currVer=$(grep -m 1 "$searchFor" "$searchFile" | head -1)

  if [[ "$currVer" =~ = ]]; then
    currVer=$(cut -d "=" -f2 <<< "$currVer")
  else
    currVer=$(awk -F ' ' '{print $3}' <<< "$currVer")
  fi

  SEARCH_TERM=$(trimmer "$trimCharacters" <<< "$currVer")
}

trimmer() {
  tr -d "$@"
}

# some images, like clojure and android, require specific URLs parsed from the web
getParsedURL() {
  local URL=$1
  local searchString=$2
  parsedURL=$(curl -sSL "$URL" | grep -m 1 "$searchString" | awk -F '/' '{ print $NF }' | tr -d "\"")
  export parsedURL
}

###
  # replaceVersions, instead of tracking the version being parsed, simply gets the latest version/url for a specific software and
  # replaces what is in the Dockerfile by specifying the the "search term", which should exist in the Dockerfile as an ENV
  # variable. The "software version" represents the actual version string of the software in a given direectory's Dockerfile
###

replaceVersions() {
  local searchTerm=$1
  local softwareVersion=$2
  # isVersion is to differentiate between replacing a version string or a URL
  local isVersion=$3

  currentVersion=$searchTerm

  if [ "$isVersion" == true ]; then
    versionEqual "$newVersion" "$softwareVersion"
    if [[ $(eval echo $?) -eq 0 ]]; then
      # shellcheck disable=SC2154
      sed -i.bak "s!$softwareVersion!""$newVersion"'!g' "$templateFile"
      find . -name \*.bak -type f -delete
    fi
  else
    # shellcheck disable=SC2154
    sed -i.bak "s!$softwareVersion!""$newVersion"'!g' "$templateFile"
    find . -name \*.bak -type f -delete
  fi
}
