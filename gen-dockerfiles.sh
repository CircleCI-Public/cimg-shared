#!/usr/bin/env bash

# A Docker image is a combination of REGISTRY/NAMESPACE/REPOSITORY[:TAG].
# Registry will be ignored for now unless we move off Docker Hub.

# Import repo-specific image information
source ./manifest

version="$1"  # SemVer version number passed in via command-line
sha="$2"  # SHA hash for the main binary of the image, passed in via command-line
tagless_image=cimg/${repository}

# prepare file
echo "#!/usr/bin/env bash" > ./build-images.sh
echo "" >> ./build-images.sh

string="docker build"

if [[ $version =~ ^[0-9]+\.[0-9]+ ]]; then
	versionShort=${BASH_REMATCH[0]}
else
	echo "Version matching failed." >&2
	# continue
fi

[[ -d "$versionShort" ]] || mkdir "$versionShort"

sed -e 's!%%PARENT%%!'"$parent"'!g' "./Dockerfile.template" > "./$versionShort/Dockerfile"
sed -i.bak 's/%%MAIN_VERSION%%/'"${version}"'/g' "./${versionShort}/Dockerfile"
sed -i.bak 's/%%VERSION_MINOR%%/'"${versionShort}"'/g' "./${versionShort}/Dockerfile"
sed -i.bak 's!%%MAIN_SHA%%!'"$sha"'!g' "./$versionShort/Dockerfile"

# This .bak thing above and below is a Linux/macOS compatibility fix
rm "./${versionShort}/Dockerfile.bak"

string="$string --file $versionShort/Dockerfile"

string="${string} -t ${tagless_image}:${version}"

if [[ $versionShort != "$version" ]]; then
	string="${string}  -t ${tagless_image}:${versionShort}"
fi

string="$string ."

echo "$string" >> ./build-images.sh


# Build a Dockerfile for each variant
# Currently this only supports shared variants, not local variants

for variant in "${variants[@]}"
do
	# If version/variant directory doesn't exist, create it
	[[ -d "${versionShort}/${variant}" ]] || mkdir "${versionShort}/${variant}"

	sed -e 's!%%PARENT%%!'"$repository"'!g' "./shared/variants/${variant}.Dockerfile.template" > "./${versionShort}/${variant}/Dockerfile"
	sed -i.bak 's/%%PARENT_TAG%%/'"${version}"'/g' "./${versionShort}/${variant}/Dockerfile"
done

# This .bak thing above and below is a Linux/macOS compatibility fix
rm "./${versionShort}/${variant}/Dockerfile.bak"

string="docker build"
string="$string --file ${versionShort}/${variant}/Dockerfile"

string="${string} -t ${tagless_image}:${version}-${variant}"

if [[ $versionShort != "$version" ]]; then
	string="${string}  -t ${tagless_image}:${versionShort}-${variant}"
fi

string="$string ."

echo "$string" >> ./build-images.sh
