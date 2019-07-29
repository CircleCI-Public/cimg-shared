#!/usr/bin/env bash

error() {
  echo "ERRROR: missing argument for $1, expected in position $2"
}

# variables
DOCKERFILE_NAME="${1:-Dockerfile}"
DOCKERFILE_PATH="${2:?$(error DOCKERFILE_PATH \`\$2\`)}"
IMAGE_NAME="${3:?$(error IMAGE_NAME \`\$3\`)}"
IMAGE_TAG="${4:?$(error IMAGE_TAG \`\$4\`)}"
GOSS_DOCKERFILE_NAME="$IMAGE_TAG-goss.Dockerfile"
GOSS_YAML_DIR_PATH="${5:?$(error GOSS_YAML_DIR_PATH \`\$5\`)}"
RESULTS_FILENAME="${6:-results.xml}"
RESULTS_DIR_PATH="${7:-test-results}"
TEST_SUITE_NAME="${8:-goss}"

echo "----------------------------------------------------------------------------------------------------"
echo "copying $DOCKERFILE_NAME for Goss modifications..."
cp "$DOCKERFILE_PATH/$DOCKERFILE_NAME" "$DOCKERFILE_PATH/$GOSS_DOCKERFILE_NAME"

# cat our additions onto the Dockerfile copy
echo "----------------------------------------------------------------------------------------------------"
echo "adding the following modifications to $GOSS_DOCKERFILE_NAME..."
echo "----------------------------------------------------------------------------------------------------"
echo "COPY goss-entrypoint.sh /""
echo "RUN sudo chmod +x /goss-entrypoint.sh || chmod +x /goss-entrypoint.sh"
echo "ENTRYPOINT ["/goss-entrypoint.sh"]""

cat >> "$DOCKERFILE_PATH/$GOSS_DOCKERFILE_NAME" \<< EOM
# first, cat goss-entrypoint.sh into whatever directory within which we are building a particular image
COPY goss-entrypoint.sh /

RUN sudo chmod +x /goss-entrypoint.sh || chmod +x /goss-entrypoint.sh

ENTRYPOINT ["/goss-entrypoint.sh"]
EOM

echo "----------------------------------------------------------------------------------------------------"
echo "copying custom Goss entrypoint for testing..."
echo "----------------------------------------------------------------------------------------------------"
echo "#!/usr/bin/env bash"
echo "# extend this if tests need more time"
echo "sleep 600"

cat > "$DOCKERFILE_PATH/goss-entrypoint.sh" \<< EOM
#!/usr/bin/env bash

# extend this if tests need more time
sleep 600
EOM

# build our test image
echo "----------------------------------------------------------------------------------------------------"
echo "building modified test image: $IMAGE_NAME/$IMAGE_TAG-goss..."
echo "----------------------------------------------------------------------------------------------------"
docker build \
  -f "$DOCKERFILE_PATH/$GOSS_DOCKERFILE_NAME" \
  -t "$IMAGE_NAME/$IMAGE_TAG-goss" \
  $DOCKERFILE_PATH

# in circleci-images, we often had to retry the image build due to flakiness
# leave this commented out for now; hopefully the simplified `cimg` setup will be less flaky
# || (sleep 2; echo "retry building $IMAGE_NAME/$IMAGE_TAG-goss"; docker build -t "$IMAGE_NAME/$IMAGE_TAG-goss" "$GOSS_DOCKERFILE_DIR_PATH")

# run goss tests
echo "----------------------------------------------------------------------------------------------------"
echo "running Goss tests against $IMAGE_NAME/$IMAGE_TAG-goss..."
echo "----------------------------------------------------------------------------------------------------"

# create/clear results directory if necessary
mkdir -p "$RESULTS_DIR_PATH"
rm -rf ${RESULTS_DIR_PATH}/*
mkdir -p "$RESULTS_DIR_PATH/$TEST_SUITE_NAME"

workdir=$(pwd)

cd "$GOSS_YAML_DIR_PATH"

# run once with normal output, for stdout
dgoss run "$IMAGE_NAME/$IMAGE_TAG-goss"

# save JUnit output to variable so we can control what we store
export GOSS_OPTS="--format junit"
results=$(dgoss run "$IMAGE_NAME/$IMAGE_TAG-goss")

cd "$workdir"

# create properly formatted JUnit XML file
echo '<?xml version="1.0" encoding="UTF-8"?>' \
  > "$RESULTS_DIR_PATH/$TEST_SUITE_NAME/$RESULTS_FILENAME"

echo "${results#*<?xml version=\"1.0\" encoding=\"UTF-8\"?>}" | \
  sed "s|testsuite name=\"goss\"|testsuite name=\"$IMAGE_NAME/$IMAGE_TAG\"|g" \
  >> "$RESULTS_DIR_PATH/$TEST_SUITE_NAME/$RESULTS_FILENAME"

echo "----------------------------------------------------------------------------------------------------"
echo "removing Goss variant..."
echo "----------------------------------------------------------------------------------------------------"
docker image rm "$IMAGE_NAME/$IMAGE_TAG-goss"
echo "----------------------------------------------------------------------------------------------------"
