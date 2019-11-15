#!/usr/bin/env bash

versions=( "$@" )

sortedVersions=$(
	for version in "${versions[@]}"; do
		echo "$version"
	done | sort --reverse)


for i in "${!sortedVersions[@]}"; do

	version=${sortedVersions[$i]}

	git checkout -b "release-v${version}"
	shared/gen-dockerfiles.sh "${version}" fake-sha
	git add .
	git commit -m "Add v${version}. [release]"
	git push -u origin "release-v${version}"
done
