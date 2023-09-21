#!/usr/bin/env bash
vers=()

###
  # Checks if the version variables are equal to each other; if versionGreaterThan evalutes to true, the version string
  # that will be passed to ./shared/release.sh will be generated and added to the vers array
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

###
  # versionGreaterThan checks if the version is greater, in which case we return a code that will then be used to determine whether
  # a version string will be generated
###

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
  # directory check is a helper function to check the given directory in order to generate a version string. It's enabled by the
  # searchTerm variable comparing the newVersion to the currentVersion
  # NOTE: because images have varying build parameters, the builtParam variable should be specified within a specific image repo
  # otherwise, the default is ""
###

directoryCheck() {
  local directory=$1
  local searchTerm=$2

  if [ -z "$builtParam" ]; then
    builtParam=""
  fi

  if [ -d "$directory" ]; then
    currentVersion=$searchTerm
    echo "directory $directory exists; checking for matching versions: $currentVersion"
    versionEqual "$newVersion" "$currentVersion"
  else
    generateVersionString "$newVersion" "$builtParam"
    return 1
  fi
}

###
  # generateVersions will help parse out the versions needed. this functions similarly to what already exists in ./shared/gen-dockerfiles
  # however, since we are pulling from a source, some parsing needs to happen; an example of ${cut} would be something like:
  # $(cut -d 'v' -f2 <<< "$version")" or just "$version" if no edits need to be made
###

generateVersions () {
  local cut=$1

  if [[ -n $cut ]]; then
    newVersion=${cut}
  else
    newVersion=${version}
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

###
  # some cimgs require a separate parameter to specify things like a URL. this function builds the full string to be included
  # in the vers array
###

generateVersionString() {
  local version=$1

  if [ -n "$builtParam" ]; then
    versionString=${version}${builtParam}
  else
    versionString=${version}
  fi

  vers+=( "$versionString" )
}

###
  # this function attempts to find the values associated with a variable in a specified Dockerfile. This is the basis for comparison
  # e.g newVersion vs currentVersion or an entire string, URL, etc that may need to be replaced
  #
###

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
  export SEARCH_TERM
}

# just in case a variable needs to be trimmed. space separated list of characters to be trimmed.

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
  # replaces what is in the Dockerfile by specifying the "search term", which should exist in the Dockerfile as an ENV
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

###
  # generateDatedTags generates tags in the form '2023.03'
###
declare -A quarters
quarters["01"]="01"
quarters["04"]="04"
quarters["07"]="07"
quarters["10"]="10"

export quarters

generateDatedTags() {
  CURRENTMONTH=$(date +%m)
  CURRENTYEAR=$(date +%Y)
  RELEASE="$CURRENTYEAR.$CURRENTMONTH"
  export RELEASE
}

# Check the mont
checkMonth() {
  if [[ ${quarters[${RELEASE##*.}]+exists} && $TEMPLATEMONTH != "${RELEASE##*.}" ]]; then
    STRING_TO_REPLACE="$TEMPLATEYEAR.$TEMPLATEMONTH"
  fi
  export STRING_TO_REPLACE
}

replaceDatedTags() {
  local templateFile=$1
  TEMPLATEYEAR=$(grep -m 1 "FROM" "$templateFile" | head -1 | cut -d : -f2 | cut -d . -f1)
  TEMPLATEMONTH=$(grep -m 1 "FROM" "$templateFile" | head -1 | cut -d : -f2 | cut -d . -f2)

  generateDatedTags
  checkMonth

  [[ -n $STRING_TO_REPLACE ]] && sed -i.bak "s|$STRING_TO_REPLACE|$RELEASE|g" "$templateFile"
}
