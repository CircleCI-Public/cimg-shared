#!/usr/bin/env bash

templateParser() {
	local parent=$1
	local namespace=$2
	local vgVersion=$3
	local versionShort=$4
	local vgParam1=$5
	local vgAlias1=$6

	sed -e 's!%%PARENT%%!'"$parent"'!g' "./Dockerfile.template" > "./$versionShort/Dockerfile"
	sed -i.bak 's!%%NAMESPACE%%!'"${namespace}"'!g' "./${versionShort}/Dockerfile"
	sed -i.bak 's!%%VERSION_FULL%%!'"${vgVersion}"'!g' "./${versionShort}/Dockerfile"
	sed -i.bak 's!%%VERSION_MINOR%%!'"${versionShort}"'!g' "./${versionShort}/Dockerfile"
	sed -i.bak 's!%%PARAM1%%!'"$vgParam1"'!g' "./$versionShort/Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"$vgAlias1"'!g' "./$versionShort/Dockerfile"
}

variantParser() {
	local repository=$1
	local namespace=$2
	local vgVersion=$3
	local versionShort=$4
	local vgParam1=$5
	local vgAlias1=$6
	local variantTemplateFile=$7

	sed -e 's!%%PARENT%%!'"$repository"'!g' "${variantTemplateFile}" > "./$versionShort/${variant}/Dockerfile"
	sed -i.bak 's!%%PARENT_TAG%%!'"${vgVersion}"'!g' "./${versionShort}/${variant}/Dockerfile"
	sed -i.bak 's!%%NAMESPACE%%!'"${namespace}"'!g' "./${versionShort}/${variant}/Dockerfile"
	sed -i.bak 's!%%VERSION_FULL%%!'"${vgVersion}"'!g' "./${versionShort}/${variant}/Dockerfile"
	sed -i.bak 's!%%VERSION_MINOR%%!'"${versionShort}"'!g' "./${versionShort}/${variant}/Dockerfile"
	sed -i.bak 's!%%PARAM1%%!'"$vgParam1"'!g' "./$versionShort/${variant}/Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"$vgAlias1"'!g' "./$versionShort/${variant}/Dockerfile"

}

nodeParser() {
	local repository=$1
	local namespace=$2
	local vgVersion=$3
	local versionShort=$4
	local vgParam1=$5
	local vgAlias1=$6
	local variantTemplateFile=$7
	variant=node

	[[ -d "${versionShort}/${variant}-${vgParam1}" ]] || mkdir "${versionShort}/${variant}-${vgParam1}"
	sed -e 's!%%PARENT%%!'"$repository"'!g' "${variantTemplateFile}" > "./$versionShort/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%PARENT_TAG%%!'"${vgVersion}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%NAMESPACE%%!'"${namespace}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%VERSION_FULL%%!'"${vgVersion}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%VERSION_MINOR%%!'"${versionShort}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%PARAM1%%!'"$vgParam1"'!g' "./$versionShort/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"$vgAlias1"'!g' "./$versionShort/${variant}-${vgParam1}/Dockerfile"

}

browserParser() {
	local repository=$1
	local namespace=$2
	local vgVersion=$3
	local versionShort=$4
	local vgParam1=$5
	local vgAlias1=$6
	local variantTemplateFile=$7
	variant=browsers

	[[ -d "${versionShort}/${variant}-${vgParam1}" ]] || mkdir "${versionShort}/${variant}-${vgParam1}"
	sed -e 's!%%PARENT%%!'"$repository"'!g' "${variantTemplateFile}" > "./$versionShort/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%PARENT_TAG%%!'"${vgVersion}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%NAMESPACE%%!'"${namespace}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%VERSION_FULL%%!'"${vgVersion}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%VERSION_MINOR%%!'"${versionShort}"'!g' "./${versionShort}/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%PARAM1%%!'"$vgParam1"'!g' "./$versionShort/${variant}-${vgParam1}/Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"$vgAlias1"'!g' "./$versionShort/${variant}-${vgParam1}/Dockerfile"

}
