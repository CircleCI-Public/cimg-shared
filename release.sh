#!/usr/bin/env bash

# Much of the version processing logic is repeated from gen-dockerfiles.sh
# This should be de-duped sometime in the future when this logic is solidified
versions=()

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

	vgVersion=$(cut -d "v" -f2- <<< "$versionGroup")
	versions+=( "$vgVersion" )
done

branchName=""
commitMSG=""

if [[ ${#versions[@]} == 0 ]]; then
	echo "Error, no versions detected."
	exit 1
elif [[ ${#versions[@]} == 1 ]]; then
	branchName="release-v${versions[0]}"
	commitMSG="Publish v${versions[0]}. [release]"
elif [[ ${#versions[@]} == 2 ]]; then
	branchName="release-v${versions[0]}-and-v${versions[1]}"
	commitMSG="Publish v${versions[0]} and v${versions[1]}. [release]"
elif [[ ${#versions[@]} == 3 ]]; then
	branchName="release-v${versions[0]}-v${versions[1]}-and-more"
	commitMSG="Publish v${versions[0]}, v${versions[1]}, and v${versions[2]}. [release]"
elif [[ ${#versions[@]} == 4 ]]; then
	branchName="release-v${versions[0]}-v${versions[1]}-and-more"
	commitMSG="Pub: v${versions[0]}, v${versions[1]}, v${versions[2]}, and more. [release]"
elif [[ ${#versions[@]} -gt 4 ]]; then
	branchName="release-v${versions[0]}-v${versions[1]}-and-more"
	commitMSG="Pub: ${versions[0]},${versions[1]},${versions[2]},${versions[3]}, and more. [release]"
fi

defaultBranch=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)

git checkout -b "${branchName}" "${defaultBranch}"
shared/gen-dockerfiles.sh "$@"
git add .
git commit -m "${commitMSG}"
git push -u origin "${branchName}"
gh pr create --title "$commitMSG" --head "$branchName" --body "$commitMSG"
