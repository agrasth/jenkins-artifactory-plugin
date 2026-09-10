#!/usr/bin/env bash
# Release script for jenkins-artifactory-plugin.
#
# Ported from the shell logic embedded in .github/workflows/release.yml so it can be
# run either as that workflow's single "Run release" step, or directly on a
# developer's machine (export the env vars below, then run this script).
#
# Expected env vars:
#   NEXT_VERSION               - version to release (e.g. 3.20.0)
#   NEXT_DEVELOPMENT_VERSION   - next development version (e.g. 3.20.x-SNAPSHOT)
#   JENKINS_ID_RSA             - SSH private key with push access to jenkinsci/artifactory-plugin
#   IL_AUTOMATION_TOKEN        - GitHub token used to push to jfrog/jenkins-artifactory-plugin
#   ARTIFACTORY_URL            - internal JFrog Artifactory URL
#   ARTIFACTORY_USER           - internal JFrog Artifactory user
#   ARTIFACTORY_APIKEY         - internal JFrog Artifactory API key
#   JENKINS_ARTIFACTORY_URL    - Jenkins Artifactory server URL
#   JENKINS_ARTIFACTORY_USER   - Jenkins Artifactory server user
#   JENKINS_ARTIFACTORY_PASSWORD - Jenkins Artifactory server password
#
# Also honored (optional, GitHub Actions only):
#   GITHUB_ENV                 - path GitHub Actions provides for persisting env vars
#                                 across steps; unused/no-op outside of Actions.

set -euo pipefail

# Configure git remotes and SSH access to the jenkinsci/artifactory-plugin upstream.
mkdir -p ~/.ssh
echo "${JENKINS_ID_RSA}" > ~/.ssh/jenkins_id_rsa
chmod 600 ~/.ssh/jenkins_id_rsa
ssh-keyscan github.com >> ~/.ssh/known_hosts

eval "$(ssh-agent)"
echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> "${GITHUB_ENV:-/dev/null}"
echo "SSH_AGENT_PID=$SSH_AGENT_PID" >> "${GITHUB_ENV:-/dev/null}"
ssh-add ~/.ssh/jenkins_id_rsa

git config user.name "JFrog CI"
git config user.email "eco-system@jfrog.com"
git checkout master
git remote set-url origin https://${IL_AUTOMATION_TOKEN}@github.com/jfrog/jenkins-artifactory-plugin.git
git remote add upstream git@github.com:jenkinsci/artifactory-plugin.git

# Make sure versions provided
echo "Checking variables"
test -n "$NEXT_VERSION" -a "$NEXT_VERSION" != "0.0.0"
test -n "$NEXT_DEVELOPMENT_VERSION" -a "$NEXT_DEVELOPMENT_VERSION" != "0.0.0"

# Configure JFrog CLI
jf c rm --quiet
jf c add internal --url=${ARTIFACTORY_URL} --access-token=${ARTIFACTORY_APIKEY}
jf mvnc --repo-resolve-releases ecosys-jenkins-repos --repo-resolve-snapshots ecosys-releases-snapshots --repo-deploy-snapshots ecosys-oss-snapshot-local --repo-deploy-releases ecosys-oss-release-local

# Run audit
jf audit --fail=false

# Update version
jf mvn versions:set -DnewVersion="${NEXT_VERSION}" -B
git commit -am "[artifactory-release] Release version ${NEXT_VERSION} [skipRun]" --allow-empty
git tag artifactory-${NEXT_VERSION}

# Run install and publish
jf mvn clean install -U -B -DskipTests
jf rt bag && jf rt bce
jf rt bp

# Distribute release bundle
jf ds rbc ecosystem-artifactory-jenkins-plugin $NEXT_VERSION --spec=./release/specs/prod-rbc-filespec.json --spec-vars="version=$NEXT_VERSION" --sign
jf ds rbd ecosystem-artifactory-jenkins-plugin $NEXT_VERSION --site="releases.jfrog.io" --sync

# Upload plugin to Jenkins Artifactory server
jf c add jenkins --url=${JENKINS_ARTIFACTORY_URL} --user=${JENKINS_ARTIFACTORY_USER} --password=${JENKINS_ARTIFACTORY_PASSWORD} --enc-password=false
jf mvnc --server-id-resolve internal --repo-resolve-releases ecosys-jenkins-repos --repo-resolve-snapshots ecosys-releases-snapshots --server-id-deploy jenkins --repo-deploy-releases releases --repo-deploy-snapshots snapshots
jf mvn clean install -U -B -DskipTests

# Update next development version
jf mvn versions:set -DnewVersion=$NEXT_DEVELOPMENT_VERSION -B
git commit -am "[artifactory-release] Next development version [skipRun]"

# Push changes
git push
git push --tags
git push upstream master
git push upstream master --tags
