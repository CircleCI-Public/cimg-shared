#!/bin/bash

REGISTRY_DIR=${REGISTRY_DIR:-"/tmp/registry"}
S3_BUCKET_NAME=${S3_BUCKET_NAME:-"cpe-images-bucket"}
source ./manifest

function parseTags() {
  if ! [ -f build-images.sh ]; then
    echo "build-images.sh does not exist. Did you forget to checkout?"
    exit 1
  fi

  # ccitest is the staging namespace; cimg is the production namespace
  sed -i "s|cimg/|ccitest/|g" "./build-images.sh"
  checkRegistryDir "$REGISTRY_DIR"

  while IFS= read -r line; do
    IFS=' ' read -ra slugs <<< "$line"
    parseNext=false

  # only select the string immediately after the tag flag
    for slug in "${slugs[@]}"; do
      if [ "$slug" == "-t" ]; then
        parseNext=true
      elif [ "$parseNext" == true ]; then
        createManifestFile "$slug"
        copyToS3 "$slug" "$S3_BUCKET_NAME"
        parseNext=false
      fi
    done
  done < build-images.sh
  createMetadataFile
}

function checkRegistryDir() {
  echo "Checking for existence of $REGISTRY_DIR directory"
  [[ -d "$REGISTRY_DIR" ]] || mkdir -p "$REGISTRY_DIR"
}

# creates a manifestfile for each tag from parsedTags, and always checks the ccitest namespace
function createManifestFile() {
  local slug=$1
  echo "Creating manifest file for $slug in $REGISTRY_DIR.."
  manifestFile=$(docker buildx imagetools inspect "$slug" --format "{{json .Manifest}}")
  echo "$manifestFile" > "$REGISTRY_DIR/${slug##*:}-manifest.json"
}

# the metadata file is what is referenced for tag and digest when copying
function createMetadataFile() {
  echo "Creating metadata.json file in $REGISTRY_DIR..."
  echo "{}" > "$REGISTRY_DIR/metadata.json"
  for file in "$REGISTRY_DIR"/*-manifest.json; do
    tag=$(basename "${file%-*}")
    jq --arg tag "$tag" --slurpfile input "$file" '. += { ($tag): $input }' "$REGISTRY_DIR/metadata.json" > tmp.json && mv tmp.json "$REGISTRY_DIR/metadata.json"
  done
}

function getTagsFromFile() {
  local file=$1
  tagList=$(jq -r 'keys[]' "${file}")
}

# Copy singular manifest files to s3, which are used as a second source for verifying breaches. Only run on merged release branches
function copyToS3 () {
  local slug=$1
  local s3Bucket=$2
  slug=${slug/ccitest/cimg}
  aws s3 cp --profile s3write "$REGISTRY_DIR/${slug##*:}-manifest.json" "s3://$s3Bucket/${slug%:*}/"
}

# Creates or appends and uploads a metadata.json to s3 that keeps a running log of all active images that have gone through this workflow and replaces
# tags if duplicated. This will be used to detect breaches
function appendToManifest() {
  local s3Bucket=$1

  if aws s3 ls --profile s3read "s3://$s3Bucket/$namespace/$repository/" | grep "metadata.json" &> /dev/null; then
    echo "Metadata file found in $namespace/$repository. Downloading to ./metadata-old.json"
    aws s3 cp --profile s3read "s3://$s3Bucket/$namespace/$repository/metadata.json" ./metadata-old.json

    getTagsFromFile "$REGISTRY_DIR/metadata.json"

    for tag in $tagList; do
      jq --slurpfile new_entries "$REGISTRY_DIR/metadata.json" --arg tag "$tag" '.[$tag] = $new_entries[0][$tag]' ./metadata-old.json > ./metadata.json
    done
    aws s3 cp --profile s3write "./metadata.json" "s3://$s3Bucket/$namespace/$repository/metadata.json"
  else
    echo "No metadata file found in $namespace/$repository. Uploading to s3"
    aws s3 cp --profile s3write "$REGISTRY_DIR/metadata.json" "s3://$s3Bucket/$namespace/$repository/metadata.json"
  fi
}

# Signs images in staging, then copies them to production once merged
function signVerifyDeploy() {
  getTagsFromFile "$REGISTRY_DIR/metadata.json"

  for tag in $tagList; do
    digest=$(jq -r ".[\"$tag\"][0].digest" "$REGISTRY_DIR/metadata.json")
    digestTag=${tag}@${digest}

      echo "Signing ccitest/$repository:$digestTag..."
      echo "y" | cosign sign --key "$KMS_KEY" "ccitest/$repository:$digestTag"

      echo "Copying image from ccitest to cimg"
      cosign copy "ccitest/$repository:$digestTag" "$namespace/$repository:$tag"

      echo "Verifying signature..."
      cosign verify --key "$KMS_KEY" "$namespace/$repository:$tag"
  done
}

function run() {
  parseTags
  signVerifyDeploy
  appendToManifest "$S3_BUCKET_NAME"
}

# Downloads the metadata file from s3 that tracks all signed images
function check() {
  aws s3 cp --profile s3write "s3://$S3_BUCKET_NAME/$namespace/$repository/metadata.json" ./metadata.json
  getTagsFromFile "./metadata.json"

  for tag in $tagList; do
    cosign verify --key "$KMS_KEY" "$namespace/$repository:$tag"
  done
}

"$@"
