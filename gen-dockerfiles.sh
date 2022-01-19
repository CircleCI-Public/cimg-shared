#!/usr/bin/env bash

# A Docker image is a combination of REGISTRY/NAMESPACE/REPOSITORY[:TAG].
# Registry will be ignored for now unless we move off Docker Hub.

# Import repo-specific image information
source ./manifest
tagless_image=${namespace}/${repository}

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
# %%MAIN_VERSION%% - deprecated, please use %%VERSION_FULL%%
# %%VERSION_MAJOR%% - just the major integer of the version such as `1`
# %%VERSION_MINOR%% - the major and minor integers of the version with a decimal in the middle such as `1.2`
# %%ALIAS1%% - what's passed as the alias when passing version strings to the build script (see above)
# %%PARAM1%% - what's passed as the paramater when passing version strings to the build script (see above)
# %%MAIN_SHA%% - deprecated, please use %%PARAM1%%

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

	[[ -d "$versionShort" ]] || mkdir "$versionShort"

	sed -e 's!%%PARENT%%!'"$parent"'!g' "./Dockerfile.template" > "./$versionShort/Dockerfile"
	sed -i.bak 's/%%NAMESPACE%%/'"${namespace}"'/g' "./${versionShort}/Dockerfile"
	sed -i.bak 's/%%MAIN_VERSION%%/'"${vgVersion}"'/g' "./${versionShort}/Dockerfile"  # will be deprecated in the future
	sed -i.bak 's/%%VERSION_FULL%%/'"${vgVersion}"'/g' "./${versionShort}/Dockerfile"
	sed -i.bak 's/%%VERSION_MINOR%%/'"${versionShort}"'/g' "./${versionShort}/Dockerfile"
	sed -i.bak 's/%%VERSION_MAJOR%%/'"${vgVersionMajor}"'/g' "./${vgVersionMinor}/Dockerfile"
	sed -i.bak 's!%%MAIN_SHA%%!'"$vgParam1"'!g' "./$versionShort/Dockerfile"  # will be deprecated in the future
	sed -i.bak 's!%%PARAM1%%!'"$vgParam1"'!g' "./$versionShort/Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"$vgAlias1"'!g' "./$versionShort/Dockerfile"

	# This .bak thing above and below is a Linux/macOS compatibility fix
	rm "./${versionShort}/Dockerfile.bak"

	string="$string --file $versionShort/Dockerfile"

	string="${string} -t ${tagless_image}:${vgVersion}"

	if [[ $versionShort != "$vgVersion" ]]; then
		string="${string}  -t ${tagless_image}:${versionShort}"
	fi

	if [[ -n $vgAlias1 ]]; then
		string="${string}  -t ${tagless_image}:${vgAlias1}"
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

		sed -e 's!%%PARENT%%!'"$repository"'!g' "${variantTemplateFile}" > "./${versionShort}/${variant}/Dockerfile"
		sed -i.bak 's/%%PARENT_TAG%%/'"${vgVersion}"'/g' "./${versionShort}/${variant}/Dockerfile"

		# This .bak thing above and below is a Linux/macOS compatibility fix
		rm "./${versionShort}/${variant}/Dockerfile.bak"

		string="docker build"
		string="$string --file ${versionShort}/${variant}/Dockerfile"

		string="${string} -t ${tagless_image}:${vgVersion}-${variant}"

		if [[ $versionShort != "$vgVersion" ]]; then
			string="${string}  -t ${tagless_image}:${versionShort}-${variant}"
		fi

		if [[ -n $vgAlias1 ]]; then
			string="${string}  -t ${tagless_image}:${vgAlias1}-${variant}"
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
