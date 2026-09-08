#!/usr/bin/env bash
# Snapshot script for jenkins-artifactory-plugin.
#
# Ported from the shell logic embedded in .github/workflows/snapshot.yml so it can be
# run either as that workflow's single "Run snapshot" step, or directly on a
# developer's machine (export the env vars below, then run this script).
#
# Expected env vars:
#   ARTIFACTORY_URL   - internal JFrog Artifactory URL
#   ARTIFACTORY_USER  - internal JFrog Artifactory user
#   ARTIFACTORY_APIKEY - internal JFrog Artifactory API key
#   GITHUB_RUN_NUMBER - build/run number used as the build-info number and the
#                        snapshot release bundle version (GitHub Actions sets this
#                        automatically; export a value when running locally)

set -euo pipefail

# Configure JFrog CLI
jf c rm --quiet
jf c add internal --url=${ARTIFACTORY_URL} --user=${ARTIFACTORY_USER} --password=${ARTIFACTORY_APIKEY}
jf mvnc --repo-resolve-releases ecosys-jenkins-repos --repo-resolve-snapshots ecosys-releases-snapshots --repo-deploy-snapshots ecosys-oss-snapshot-local --repo-deploy-releases ecosys-oss-release-local

# Run audit
jf audit --fail=false

# Delete former snapshots to make sure the release bundle will not contain the same artifacts
jf rt del "ecosys-oss-snapshot-local/org/jenkins-ci/plugins/artifactory/*" --quiet

# Run install and publish
jf mvn clean install -U -B javadoc:jar source:jar
jf rt bag && jf rt bce
jf rt bp

# Distribute release bundle
jf ds rbc ecosystem-artifactory-jenkins-plugin-snapshot ${GITHUB_RUN_NUMBER} --spec=./release/specs/dev-rbc-filespec.json --sign
jf ds rbd ecosystem-artifactory-jenkins-plugin-snapshot ${GITHUB_RUN_NUMBER} --site="releases.jfrog.io" --sync
