#!/usr/bin/env bash

# VARIABLES
DOCKERFILE_PATH="$1" # path to original Dockerfile for the image being tested
GOSS_DOCKERFILE_DIR_PATH="$2" # path at which to create directory for Goss Dockerfile and build context

ORIGINAL_IMAGE_NAME="$3" # name of original image being tested, e.g., `cimg/node`
ORIGINAL_IMAGE_TAG="$4" # tag of original image being tested, e.g., `2019-Q3`

RESULTS_FILENAME="$5" # name of file (must end in .xml) in which to store JUnit test results for this particular image variant, e.g., `2019-Q3.xml`
RESULTS_DIR_PATH="$6" # path at which to create directory for test results, e.g., `node`

# create directory for Goss Dockerfile and build context
mkdir $GOSS_DOCKERFILE_DIR_PATH

echo "----------------------------------------------------------------------------------------------------"
echo "copying Dockerfile to $GOSS_DOCKERFILE_DIR_PATH for Goss modifications..."
cp "$DOCKERFILE_PATH" "$GOSS_DOCKERFILE_DIR_PATH"

# cat our additions onto the Dockerfile copy
echo "----------------------------------------------------------------------------------------------------"
echo "adding the following modifications to Goss Dockerfile..."
echo "----------------------------------------------------------------------------------------------------"
cat goss-add.Dockerfile
cat goss-add.Dockerfile >> "$GOSS_DOCKERFILE_DIR_PATH/Dockerfile"

echo "----------------------------------------------------------------------------------------------------"
echo "copying custom Goss entrypoint for testing..."
echo "----------------------------------------------------------------------------------------------------"
cat goss-entrypoint.sh
cp goss-entrypoint.sh "$GOSS_DOCKERFILE_DIR_PATH"

# build our test image
echo "----------------------------------------------------------------------------------------------------"
echo "building modified test image: $ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss..."
echo "----------------------------------------------------------------------------------------------------"
docker build -t "$ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss" "$GOSS_DOCKERFILE_DIR_PATH"

# in circleci-images, we often had to retry the image build due to flakiness
# leave this commented out for now; hopefully the simplified `cimg` setup will be less flaky
# || (sleep 2; echo "retry building $ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss"; docker build -t "$ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss" "$GOSS_DOCKERFILE_DIR_PATH")

# run goss tests
echo "----------------------------------------------------------------------------------------------------"
echo "running Goss tests on $ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss..."
echo "----------------------------------------------------------------------------------------------------"

# run once with normal output, for stdout
dgoss run "$ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss"

# save JUnit output to variable so we can control what we store
export GOSS_OPTS="--format junit"
results=$(dgoss run "$ORIGINAL_IMAGE_NAME"/"$ORIGINAL_IMAGE_TAG-goss")

# create properly formatted JUnit XML file
echo '<?xml version="1.0" encoding="UTF-8"?>' > \
 "$RESULTS_DIR_PATH/$RESULTS_FILENAME"
echo "${results#*<?xml version=\"1.0\" encoding=\"UTF-8\"?>}" | \
  sed "s|testsuite name=\"goss\"|testsuite name=\"$ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG\"|g" >> \
 "$RESULTS_DIR_PATH/$RESULTS_FILENAME"

echo "----------------------------------------------------------------------------------------------------"
echo "removing Goss variant..."
echo "----------------------------------------------------------------------------------------------------"
docker image rm "$ORIGINAL_IMAGE_NAME/$ORIGINAL_IMAGE_TAG-goss"
echo "----------------------------------------------------------------------------------------------------"
