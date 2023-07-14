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
echo "set -eo pipefail" >> ./build-images.sh
chmod +x ./build-images.sh
echo "" >> ./build-images.sh

if [[ $arm64 == "1" ]]; then
	echo "docker context create cimg"  >> ./build-images.sh
	echo "docker buildx create --use cimg"  >> ./build-images.sh
fi

touch push-images-temp.sh
echo "#!/usr/bin/env bash" > ./push-images.sh
echo "# Do not edit by hand; please use build scripts/templates to make changes" >> ./push-images.sh
echo "set -eo pipefail" >> ./push-images.sh
chmod +x ./push-images.sh

export CREATE_VERSIONS=("$@")

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
# %%MAIN_VERSION%% - deprecated, please use %%VERSION_FULL%% instead
# %%VERSION_MAJOR%% - just the major integer of the version such as `1`
# %%VERSION_MINOR%% - the major and minor integers of the version with a decimal in the middle such as `1.2`
# %%ALIAS1%% - what's passed as the alias when passing version strings to the build script (see above)
# %%PARAM1%% - what's passed as the paramater when passing version strings to the build script (see above)
# %%MAIN_SHA%% - deprecated, please use %%PARAM1%%

#####
# Helper functions.
#####

# Parses all template variables, regardless of if it's a main or variant image
parse_template_variables () {
	
	local variantPath=${1}
	local parent=${2}
	local fileTemplate=${3}
	local parentTag=${4}
	local directory=${5}

	[[ -d "$directory" ]] || mkdir "$directory"

	sed -e 's!%%PARENT%%!'"${parent}"'!g' "${fileTemplate}" > "./${versionShort}/${variantPath}Dockerfile"
	sed -i.bak 's/%%PARENT_TAG%%/'"${parentTag}"'/g' "./${versionShort}/${variantPath}Dockerfile"
	sed -i.bak 's/%%NAMESPACE%%/'"${namespace}"'/g' "./${versionShort}/${variantPath}Dockerfile"
	sed -i.bak 's/%%MAIN_VERSION%%/'"${vgVersion}"'/g' "./${versionShort}/${variantPath}Dockerfile" # will be deprecated in the future
	sed -i.bak 's/%%VERSION_FULL%%/'"${vgVersion}"'/g' "./${versionShort}/${variantPath}Dockerfile"
	sed -i.bak 's/%%VERSION_MINOR%%/'"${versionShort}"'/g' "./${versionShort}/${variantPath}Dockerfile"
	sed -i.bak 's/%%VERSION_MAJOR%%/'"${vgVersionMajor}"'/g' "./${vgVersionMinor}/${variantPath}Dockerfile"
	sed -i.bak 's!%%MAIN_SHA%%!'"$vgParam1"'!g' "./$versionShort/${variantPath}Dockerfile" # will be deprecated in the future
	sed -i.bak 's!%%PARAM1%%!'"${vgParam1}"'!g' "./${versionShort}/${variantPath}Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"${vgAlias1}"'!g' "./${versionShort}/${variantPath}Dockerfile"
}

build_and_push() {
	local pathing=${1}
	local versionString=${2}
	local versionShortString=${3}
	local defaultString=${4}
	local defaultShortString=${5}

	# every version loop will generate these basic docker tags
	# if parentTags are enabled, then additional tags will be generated in the parentTag loop
	# the defaultString is referenced as the tag that should be given by default for either a parent Tag or an alias
	
	if [[ -z "$arm64" ]]; then
		echo "docker push $tagless_image:$versionShortString" >> ./push-images-temp.sh
		echo "docker push $tagless_image:$versionString" >> ./push-images-temp.sh
		echo "docker build --file $pathing/Dockerfile -t $tagless_image:$versionString -t $tagless_image:$versionShortString --platform linux/amd64 ." >> ./build-images-temp.sh
	elif [[ $pathing == *"browsers"* ]]; then
		echo "docker buildx build --platform=linux/amd64 --file $pathing/Dockerfile -t $tagless_image:$versionString -t $tagless_image:$versionShortString --push ." >> ./build-images-temp.sh
	else
		echo "docker buildx build --platform=linux/amd64,linux/arm64 --file $pathing/Dockerfile -t $tagless_image:$versionString -t $tagless_image:$versionShortString --push ." >> ./build-images-temp.sh
	fi

	if [[ -n $defaultParentTag ]] && [[ "$defaultParentTag" == "$parentTag" ]]; then
		if [[ -z "$arm64" ]]; then
			{ 
				echo "docker tag $tagless_image:$versionString $tagless_image:$defaultString"
				echo "docker tag $tagless_image:$versionShortString $tagless_image:$defaultShortString"
				echo "docker push $tagless_image:$defaultShortString"
				echo "docker push $tagless_image:$defaultString"
			} >> ./push-images-temp.sh
		fi
	fi
	
	if [[ -n $vgAlias1 ]] && [[ "$vgVersion" = "$aliasGroup" ]]; then
		if [[ -z "$arm64" ]]; then
			{
				echo "docker tag $tagless_image:$versionString $tagless_image:$defaultString"
				echo "docker push $tagless_image:$defaultString"
			} >> ./push-images-temp.sh
		else
			{
				echo "docker buildx imagetools create -t $tagless_image:$defaultString $tagless_image:$versionString"
			} >> ./push-images-temp.sh
		fi
	fi
}

filepath_templating () {
	if [[ -f "./variants/${variant}.Dockerfile.template" ]]; then
		fileTemplate="./variants/${variant}.Dockerfile.template"
	elif [[ -f "./shared/variants/${variant}.Dockerfile.template" ]]; then
		fileTemplate="./shared/variants/${variant}.Dockerfile.template"
	else 
		echo "Error: Variant ${variant} doesn't exist. Exiting."
		exit 2
	fi
}

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
		aliasGroup="${versionGroup}"
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

	[[ -d "$versionShort" ]] || mkdir "$versionShort"

	# no parentTag loop; creates Dockerfiles and variants
	if [[ -z "${parentTags[0]}" ]]; then
		parse_template_variables "" "$parent" "./Dockerfile.template" "$vgVersion" "$versionShort"
		build_and_push "$versionShort" "$vgVersion" "$versionShort" "$vgAlias1"

		for variant in "${variants[@]}"; do
			filepath_templating
			parse_template_variables "$variant/" "$repository" "$fileTemplate" "$vgVersion" "$versionShort/$variant"
			build_and_push "$versionShort/$variant" "$vgVersion-$variant" "$versionShort-$variant" "$vgAlias1-$variant"
		done
	else

	# parentTag loop; one Dockerfile will be created along with however many variants there are for each parentTag
		for parentTag in "${parentTags[@]}"; do
			if [[ -n $parentTag ]]; then
				parse_template_variables "$parentTag/" "$parent" "./Dockerfile.template" "$parentTag" "$versionShort/$parentTag"
				build_and_push "$versionShort/$parentTag" "$vgVersion-$parentSlug-$parentTag" "$versionShort-$parentSlug-$parentTag" "$vgVersion" "$versionShort"
				
				for variant in "${variants[@]}"; do
					filepath_templating
					parse_template_variables "$parentTag/$variant/" "$repository" "$fileTemplate" "$vgVersion-$parentSlug-$parentTag" "$versionShort/$parentTag/$variant"
					build_and_push "$versionShort/$parentTag/$variant" "$vgVersion-$parentSlug-$parentTag-$variant" "$versionShort-$parentSlug-$parentTag-$variant" "$vgVersion-$variant" "$versionShort-$variant"
				done
			fi
		done
	fi
	# Build out the ALIASES file. Keeps track of aliases that have been set
	# without losing old versions.
	if [[ -n $vgAlias1 ]] && [[ $aliasGroup = "$versionGroup" ]]; then
		if [[ -f ALIASES ]]; then
			# Make sure the current alias isn't in the file.
			grep -v "${vgAlias1}" ./ALIASES > ./TEMP && mv ./TEMP ./ALIASES
		fi

		echo "${vgAlias1}=${vgVersion}" >> ALIASES
	fi

	# This .bak thing fixes a Linux/macOS compatibility issue, but the files are cleaned up
	find . -name \*.bak -type f -delete
done

if [[ -n "${CREATE_VERSIONS}" ]]; then
		# Make sure the current alias isn't in the file.
	if [[ -f GEN-CHECK ]]; then
		grep -v "${CREATE_VERSIONS}" ./GEN-CHECK > ./TEMP2 && mv ./TEMP2 ./GEN-CHECK
	fi

	echo "GEN_CHECK=($@)" > GEN-CHECK
	if [[ -f TEMP2 ]]; then
		rm ./TEMP2
	fi
fi

cat -n push-images-temp.sh | sort -uk2 | sort -nk1 | cut -f2- >> push-images.sh
cat -n build-images-temp.sh | sort -uk2 | sort -nk1 | cut -f2- >> build-images.sh
rm push-images-temp.sh build-images-temp.sh
