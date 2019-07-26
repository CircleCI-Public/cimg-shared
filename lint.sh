#! /usr/bin/env bash
#
# designed to be run from a `cimg` image repo that has imported these
# shared scripts as a submodule.
#
# must be run from the repo's root, e.g., bash shared/lint.sh
#
# linting ignore and trusted registry rules can be passed as a
# comma-separated string, e.g., `DL3000,SC1010`, or they will be drawn
# from any `.hadolint.yaml` file in the repo's root
#
# for Dockerfiles, pass a comma-separated string, or shell expression
# that will resolve as a comma-separated string, of relative or absolute
# paths, including name, to Dockerfiles to be linted, e.g.,
# `~/project/app/deploy.Dockerfile,~/project/app/test.Dockerfile`, or
# `$(find */*/Dockerfile | tr '\n' ',')`
#
# example command usage:
#
# bash shared/lint.sh -i DL3000,SC1010 -- app/test.Dockerfile,app/deploy.Dockerfile
# bash shared/lint.sh --ignore-rules SC1010 -t docker.io -- "$(find */Dockerfile | tr '\n' ',')"
# bash shared/lint.sh --trusted-registries my.registry:5000 -- Dockerfile
# bash shared/lint.sh -- "$(find */*/Dockerfile | tr '\n' ',')"


die() {
  printf '%s\n' "$1" >&2
  exit 1
}

# Initialize all the option variables
# This ensures we are not contaminated by variables from the environment
IGNORE_STRING=
IGNORE_RULES=
REGISTRIES_STRING=
TRUSTED_REGISTRIES=

printf "Running hadolint with the following options...\n\n"

while :; do
	case $1 in
		-i|--ignore-rules)
			if [ "$2" ]; then
				if [[ $(echo "$2" | grep DL) || $(echo "$2" | grep SC) ]]; then
					IGNORE_STRING="$2"
					IGNORE_RULES=$(echo "--ignore ${IGNORE_STRING//,/ --ignore }")
					printf "Ignore rules: %s\n\n" "$IGNORE_RULES"
					shift
				else
					die "ERROR: unknown option for \`--ignore-rules\`: \`$2\`"
				fi
			else
				die 'ERROR: `--ignore-rules` requires a non-empty option argument'
			fi
			;;
		-t|--trusted-registries)
			if [ "$2" ]; then
				REGISTRIES_STRING="$2"
				TRUSTED_REGISTRIES=$(echo "--trusted-registry ${REGISTRIES_STRING//,/ --trusted-registry }")
				printf "Trusted registries: %s\n\n" "$TRUSTED_REGISTRIES"
				shift
			else
				die 'ERROR: `--trusted-registries` requires a non-empty option argument'
			fi
			;;
		--)              # End of all options
			shift
			break
			;;
		-?*)
			die "ERROR: unknown option: \`$1\`
            expecting: \`-- DOCKERFILES\`"
			;;
		*)               # Default case: No more options, so break out of the loop
			break
	esac
	shift
done

# Rest of the program here
# If there are arguments (for example) that follow the options, they
# will remain in the "$@" positional parameters

if [ -f .hadolint.yaml ]; then
	printf 'Contents of `.hadolint.yaml` file:\n\n'
	cat .hadolint.yaml && printf '\n'
fi

DOCKERFILES="$1"

# use comma delimiters to create array
arrDOCKERFILES=($(echo "${DOCKERFILES//,/ }"))
let END=${#arrDOCKERFILES[@]}

for ((i=0;i<END;i++)); do
  DOCKERFILE="{arrDOCKERFILES[i]}"

  hadolint "$IGNORE_RULES" "$TRUSTED_REGISTRIES" $DOCKERFILE

  echo "Success! $DOCKERFILE linted; no issues found"
done
