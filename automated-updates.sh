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
  local newVersion=$1
  local currentVersion=$2
  local paramVariable=$3

  if [ "$newVersion" = "$currentVersion" ]; then
    echo "Current version $currentVersion matches $newVersion. Does not need an update"
    return 1
  else
    versionGreaterThan "$newVersion" "$currentVersion" "$paramVariable"
  fi
}

###
  # paramVariable here refers to the extra parameter a specific repo utilizes. Some examples include:
  # node: uses the "=" to designate an additional parameter specifying lts or current
  # openJDK: uses the "#" to designate the specific URL of the binary download
###

versionGreaterThan() {
  local newVersion=$1
  local currentVersion=$2
  local paramVariable=$3

  if [ "$(printf '%s\n' "$newVersion" "$currentVersion" | sort -V | head -n1)" = "$currentVersion" ]; then
    echo "Parsed version $newVersion is greater than $currentVersion"
    if [ -n "${paramVariable}" ]; then
      case $paramVariable in
      lts)
        vers+=( "$newVersion=lts" )
        ;;
      current)
        vers+=( "$newVersion=current" )
        ;;
      *adoptium*)
        vers+=( "$newVersion#$paramVariable" )
        ;;
      *clojure*)
        vers+=( "$newVersion#$paramVariable" )
        ;;
      *)
        vers+=( "$newVersion" )
        ;;
      esac
    else
      vers+=( "$newVersion" )
    fi
  else
    echo "Parsed version $newVersion is not greater than $currentVersion"
  fi
}

### as more modules for cimgs are added, add to the case statement to get your desired parameter

newVers() {
  local newVersion=$1
  local paramVariable=$2
  echo "directory does not exist; $newVersion is a new version"
  if [ -n "${paramVariable}" ]; then
    case $paramVariable in
      lts)
        vers+=( "$newVersion=lts" )
        ;;
      current)
        vers+=( "$newVersion=current" )
        ;;
      *adoptium*)
        vers+=( "$newVersion#$paramVariable" )
        ;;
      *clojure*)
        verss+=("$nerVersion#$paramVariable" )
        ;;
      *)
        vers+=( "$newVersion" )
    esac
  else
      vers+=( "$newVersion" )
  fi
}

###
  # directory check is simply a helper function to check the given directory in order to call newVers or not; it is enabled
  # by the "searchTerm" variable, which is nested within each "get" function in order to determine the currentVersion we are
  # comparing the newVersion to
###

directoryCheck() {
  local directory=$1
  local searchTerm=$2
  local paramVariable=$3

  if [ -d "$directory" ]; then
    currentVersion=$searchTerm
    echo "directory $directory exists; checking for matching versions: $currentVersion"
    versionEqual "$newVersion" "$currentVersion" "$paramVariable"
  else
    newVers "$newVersion" "$paramVariable"
  fi
}

# parameter builder for cimgs like openjdk, clojure, node

buildParameter() {
  local newVersionString=$1

  if [ -n "$EXTRA_PARAM" ]; then
    case $CIRCLE_PROJECT_REPONAME in
      *cimg-node*)
        case $newVersionString in
          19.*)
            export builtParam=current
            ;;
          18.*)
            export builtParam=lts
            ;;
          *)
            export builtParam=""
            ;;
        esac
        ;;
      *cimg-openjdk*)
        if [[ $newVersionString =~ ^8.0 ]]; then
          export builtParam="https://github.com/adoptium/temurin8-binaries/releases/download/$dirtyVersion/OpenJDK8U-jdk_x64_linux_hotspot_$newFullVersion$buildVersion.tar.gz"
        else
          # shellcheck disable=SC2154
          # jdkver should be used as a variable in the wrapping loop for openjdk
          export builtParam="https://github.com/adoptium/temurin$jdkver-binaries/releases/download/jdk-$newVersionString%2B$buildVersion/OpenJDK${jdkver}U-jdk_x64_linux_hotspot_${newVersionString}_$buildVersion.tar.gz"
        fi
        ;;
      *cimg-clojure*)
        export builtParam="https://download.clojure.org/install/$newVersionString"
        ;;
      *)
        export builtParam=""
        ;;
    esac
  else
    unset builtParam
  fi
}

# version cleaner. many of the get functions have statements that can be added into this

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
}

generateSearchTerms () {
  local searchFor=$1
  local searchFile=$2
  local trimCharacters=$3

  currVer=$(grep -m 1 "$searchFor" "$searchFile" | head -1 | cut -d "=" -f2)
  if [[ $currVer =~ [0-9]+(\.[0-9]+)*$ ]]; then
    currVer=$(cut -d "-" -f1 <<< "$currVer")
  else
    currVer=$(echo "$currVer" | cut -d "/" -f6 | cut -d "\"" -f1)
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

versionCleaner () {
  local dirtyVersion=$1

  case $dirtyVersion in
    jdk8u+([0-9]*))
      buildVersion=$(cut -d "-" -f2 <<< "${dirtyVersion}")
      generateVersions "$dirtyVersion" "$(cut -d "-" -f1 <<< "${dirtyVersion}")"
      newFullVersion=$(echo "$newVersion" | trimmer "j d k" | sed -r 's/u/.0./g')
      newVersion=${newFullVersion}
      ;;
    jdk-+([0-9])*)
      generateVersions "$dirtyVersion" "$(cut -d "-" -f2 <<< "${dirtyVersion}")"
      buildVersion=$(cut -d "+" -f2 <<< "${newVersion}")
      newVer=${newVersion%+*}
      if [[ $newVer =~ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]) ]]; then
        newVersionExtended=${newVersion%+*}
        newVersion=$newVer
      else
        newVersion=$newVer
      fi
      ;;
    *)
      echo "Nothing to clean"
    ;;
  esac

  majorMinor=${newVersion%.*}
}

###
  # replaceVersions, instead of tracking the version being parsed, simply gets the latest version for a specific software and
  # replaces what is in the Dockerfile by specifying the the "search term", which should exist in the Dockerfile as an ENV
  # variable. The "software version" represents the actual version string of the software in a given direectory's Dockerfile
###

replaceVersions() {
  local searchTerm=$1
  local softwareVersion=$2

  currentVersion=$searchTerm
  if [[ $(versionEqual "$newVersion" "$softwareVersion") =~ 'is greater' ]]; then
  # templateFile will be given as part of the function that uses replaceVersions
  # shellcheck disable=SC2154
    sed -i.bak "s!$softwareVersion!""$newVersion"'!g' "$templateFile"
    find . -name \*.bak -type f -delete
  fi
}

###
  # get functions for specific convenience images. Because naming conventions are not always clean and because there are so many.
  # this is the general convenience image version updater. However, there will be excpections, like java, will will require
  # additional functions like replaceVersions or buildParameters
###

getVersions() {
  local RSS_URL=$1
  # link to the feed that the function will parse
  # for example: "https://github.com/python/cpython/tags.atom"
  local VERSIONS=$2
  # parse string based on the contents of $RSS_URL
  # for example: $(curl --silent "$RSS_URL" | grep -E '(title)' | tail -n +2 | sed -e 's/^[ \t]*//' | sed -e 's/<title>//' -e 's/<\/title>//')
  # defaults to above, but some are different
  local stringMatch=$3
  # specific string or strings to match to the regex when parsing
  # for example: $version =~ ^v[0-9]+(\.[0-9]+)*$
  local cutVersion=$4
  # tags will often come with extraneous characters that we want to parse out
  # for example: v10.10.10 "$(cut -d 'v' -f2 <<< "$version")"
  local searchString=$5
  # since our variables are defined in Dockerfiles, we can specify what term to look for
  # for example: PYTHON_VERSION= or LEIN_VERSION=
  local directoryPrefix=$6
  # because some cimgs will have dated directories, you can change this or this will default to $majorMinor
  local cutChars=$7
  # uses tr to trim specific characters separated by a space
  # example: "'\\' '=' ' ' '\"' '-'"

  if [ -z "$directoryPrefix" ]; then
    directoryPrefix=$majorMinor
  fi

  if [ -z "$VERSIONS" ]; then
    VERSIONS=$(curl --silent "$RSS_URL" | grep -E '(title)' | tail -n +2 | sed -e 's/^[ \t]*//' | sed -e 's/<title>//' -e 's/<\/title>//')
  fi

  for version in $VERSIONS; do
    if [[ $stringMatch ]]; then
      generateVersions "$version" "$cutVersion"
      generateSearchTerms "$searchString" "$directoryPrefix/Dockerfile" "$cutChars"
      case $CIRCLE_PROJECT_REPONAME in
        *cimg-node*)
          EXTRA_PARAM=true
          buildParameter "$newVersion"
          directoryCheck "$majorMinor" "$SEARCH_TERM" "$builtParam"
          unset builtParam
          ;;
        *cimg-openjdk*)
          EXTRA_PARAM=true
          if [[ $newVersionExtended == "$newVersion" ]]; then
            buildParameter "$newVersionExtended"
          else
            buildParameter "$newVersion"
          fi
          directoryCheck "$majorMinor" "$SEARCH_TERM" "$builtParam"
          unset builtParam
          ;;
        *cimg-clojure*)
          EXTRA_PARAM=true
          getParsedURL https://clojure.org/guides/install_clojure\#_linux_instructions "linux-install-"
          buildParameter "$parsedURL"
          directoryCheck "$majorMinor" "$SEARCH_TERM" "$builtParam"
          unset builtParam
          ;;
        *)
          directoryCheck "$majorMinor" "$SEARCH_TERM"
          ;;
      esac
    fi
  done
}
