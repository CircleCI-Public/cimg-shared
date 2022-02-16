#!/usr/bin/env bash

# A Docker image is a combination of REGISTRY/NAMESPACE/REPOSITORY[:TAG].
# Registry will be ignored for now unless we move off Docker Hub.

# Import repo-specific image information
source ./manifest
tagless_image=${namespace}/${repository}

# Import parsing functions
source ./parsers.sh
chmod +x ./parsers.sh

# Prepare the build and push files. Originally we only needed a build file but
# with modern versions of Docker, a push file became neccesary as well.
echo "#!/usr/bin/env bash" > ./build-images.sh
echo "# Do not edit by hand; please use build scripts/templates to make changes" >> ./build-images.sh
chmod +x ./build-images.sh
echo "" >> ./build-images.sh

echo "#!/usr/bin/env bash" > ./push-images.sh
echo "# Do not edit by hand; please use build scripts/templates to make changes" >> ./push-images.sh
chmod +x ./push-images.sh

# A version can be a major.minor or major.minor.patch version string.
# An alias can be passed right after the version with an equal sign (=).
# An additional parameter can be passed with a hash (#) sign.
# Additionally versions/version groups are separated by spaces.
#
# Examples:
#
# 1.13.1 v1.14.2
# v1.13.1#sha256abcfabdbc674bcg
# v13.0.1=lts
# v20.04
# v8.0.252=lts=https://example.com/download/item.tar-gz
#
# Template variables exists in the `Dockerfile.template` files. The start and
# end with two percent symbles `%%`. During Dockerfile generation, they get
# replaced with actual valuables. Here's what's available to use:
#
# %%VERSION_FULL%% - the complete version passed to the script such as `1.2.3`
# %%VERSION_MAJOR%% - just the major integer of the version such as `1`
# %%VERSION_MINOR%% - the major and minor integers of the version with a decimal in the middle such as `1.2`
# %%ALIAS1%% - what's passed as the alias when passing version strings to the build script (see above)
# %%PARAM1%% - what's passed as the paramater when passing version strings to the build script (see above)

#####
# Starting version loop.
#####
for versionGroup in "$@"; do

	# Process the version group(s) that were passed to this script.
	if [[ "$versionGroup" == *"#"* ]]; then
		vgParam1=$(cut -d "#" -f2- <<< "$versionGroup")
		versionGroup="${versionGroup//$vgParam1}"
		versionGroup="${versionGroup//\#}"
	fi

	if [[ "$versionGroup" == *"="* ]]; then
		vgAlias1=$(cut -d "=" -f2- <<< "$versionGroup")
		versionGroup="${versionGroup//$vgAlias1}"
		versionGroup="${versionGroup//=}"
	fi

	vgVersionFull=$(cut -d "v" -f2- <<< "$versionGroup")
	vgVersion=$vgVersionFull  # will be deprecated in the future

	if [[ $vgVersionFull =~ ^[0-9]+\.[0-9]+ ]]; then
		vgVersionMinor=${BASH_REMATCH[0]}
		versionShort=$vgVersionMinor  # will be deprecated in the future
	else
		echo "Version matching (minor) failed." >&2
		exit 1
	fi

	if [[ $vgVersionFull =~ ^[0-9]+ ]]; then
		vgVersionMajor=${BASH_REMATCH[0]}
	else
		echo "Version matching (major) failed." >&2
		exit 1
	fi

	string="docker build"

	# Makes a version folder if it doesn't already exist
	[[ -d "$versionShort" ]] || mkdir "$versionShort"

	# Parses through template variables and replaces matching strings
	templateParser "$parent" "$namespace" "$vgVersion" "$versionShort" "$vgVersionMajor" "$vgParam1" "$vgAlias1"

	# Removes files associated with Linux/MacOS compatability fix for sed
	if [[ -e "./$versionShort/Dockerfile.bak" ]]; then
		rm "./$versionShort/Dockerfile.bak"
	fi

	string="$string --file $versionShort/Dockerfile"

	string="${string} -t ${tagless_image}:${vgVersion}"

	if [[ $versionShort != "$vgVersion" ]]; then
		string="${string}  -t ${tagless_image}:${versionShort}"
	fi

	if [[ -n $vgAlias1 ]]; then
		string="${string}  -t ${tagless_image}:${vgAlias1}"
	fi

	if [[ -n $vgParam1 ]]; then
		string="${string}  -t ${tagless_image}:${versionShort}-${vgParam1}"
	fi

	string="$string ."

	echo "$string" >> ./build-images.sh

	echo "" >> ./push-images.sh

	# push main tag
	echo "docker push ${tagless_image}:${vgVersion}" >> ./push-images.sh

	# potentially push semver alias tag
	
	if [[ $versionShort != "$vgVersion" ]]; then
		echo "docker push ${tagless_image}:${versionShort}" >> ./push-images.sh
	fi

	# potentially push alias tag
	if [[ -n $vgAlias1 ]]; then
		echo "docker push ${tagless_image}:${vgAlias1}" >> ./push-images.sh
	fi

	#potentially push param tag
	if [[ -n $vgParam1 ]]; then
		echo "docker push ${tagless_image}:${versionShort}-${vgParam1}" >> ./push-images.sh
	fi

	# Build a Dockerfile for each variant
	# Currently this only supports shared variants, not local variants
	for variant in "${variants[@]}"; do

		# Check if variant is local, shared, or doesn't exists
		if [[ -f "./variants/${variant}.Dockerfile.template" ]]; then
			variantTemplateFile="./variants/${variant}.Dockerfile.template"
		elif [[ -f "./shared/variants/${variant}.Dockerfile.template" ]]; then
			variantTemplateFile="./shared/variants/${variant}.Dockerfile.template"
		else
			echo "Error: Variant ${variant} doesn't exists. Exiting."
			exit 2
		fi
		# If version/variant directory doesn't exist, create it
		[[ -d "${versionShort}/${variant}" ]] || mkdir "${versionShort}/${variant}"

		# Accounts for different variants and parses multiple template variables in order to generate Dockerfile
		# Hardcoded variables are default values
		if [[ $variant == "browsers" ]]; then
			variantParser "$parent" "$namespace" "$vgVersion" "$versionShort" "$vgVersionMajor" "openjdk-11" "$vgAlias1"
		fi
		if [[ $variant == "node" ]]; then
			variantParser "$parent" "$namespace" "$vgVersion" "$versionShort" "$vgVersionMajor" "lts" "$vgAlias1"
		fi
	
		if [[ $vgParam1 =~ v[0-9][0-9] ]] && [[ $variant = "node" ]]; then
			[[ -d "${versionShort}/node-${vgParam1}" ]] || mkdir "${versionShort}/node-${vgParam1}"
			nodeParser "$repository" "$namespace" "$vgVersion" "$versionShort" "$vgVersionMajor" "$vgParam1" "$vgAlias1"
			echo "docker push ${tagless_image}:${vgAlias1}-node-${vgParam1}" >> ./push-images.sh
		fi
		if [[ $vgParam1 =~ open ]] && [[ $variant = "browsers" ]]; then
			[[ -d "${versionShort}/browsers-${vgParam1}" ]] || mkdir "${versionShort}/browsers-${vgParam1}"
			browserParser "$repository" "$namespace" "$vgVersion" "$versionShort" "$vgVersionMajor" "$vgParam1" "$vgAlias1"
			echo "docker push ${tagless_image}:${vgAlias1}-browsers-${vgParam1}" >> ./push-images.sh
		fi

		# This .bak thing above and below is a Linux/macOS compatibility fix
		if [[ -f "./${versionShort}/${variant}/Dockerfile.bak" ]]; then
			rm "./${versionShort}/${variant}/Dockerfile.bak"
		fi

		if [[ -f "./${versionShort}/${variant}-${vgParam1}/Dockerfile.bak" ]]; then
			rm "./${versionShort}/${variant}-${vgParam1}/Dockerfile.bak"
		fi

		string="docker build"
		string="$string --file ${versionShort}/${variant}/Dockerfile"

		string="${string} -t ${tagless_image}:${vgVersion}-${variant}"

		if [[ $versionShort != "$vgVersion" ]]; then
			string="${string}  -t ${tagless_image}:${versionShort}-${variant}"
		fi

		if [[ -n $vgAlias1 ]]; then
			string="${string}  -t ${tagless_image}:${vgAlias1}-${variant}"
		fi

		if [[ -n $vgParam1 ]]; then
			string="${string}  -t ${tagless_image}:${vgAlias1}-${variant}-${vgParam1}"
		fi

		string="$string ."

		echo "$string" >> ./build-images.sh

		# push the variant tag
		echo "docker push ${tagless_image}:${vgVersion}-${variant}" >> ./push-images.sh

		# potentially push the semver alias alias tag
		if [[ $versionShort != "$vgVersion" ]]; then
			echo "docker push ${tagless_image}:${versionShort}-${variant}" >> ./push-images.sh
		fi

		# potentially push the semver alias alias tag
		if [[ -n $vgAlias1 ]]; then
			echo "docker push ${tagless_image}:${vgAlias1}-${variant}" >> ./push-images.sh
		fi
	done

	# Build out the ALIASES file. Keeps track of aliases that have been set
	# without losing old versions.
	if [[ -n $vgAlias1 ]]; then
		if [[ -f ALIASES ]]; then
			# Make sure the current alias isn't in the file.
			grep -v "${vgAlias1}" ./ALIASES > ./TEMP && mv ./TEMP ./ALIASES
		fi

		echo "${vgAlias1}=${vgVersion}" >> ALIASES
	fi
done
