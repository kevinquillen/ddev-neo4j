#!/usr/bin/env bats

# Integration tests for the kevinquillen/ddev-neo4j add-on, run via bats-core.
#
# Local prerequisites (macOS):
#   brew install bats-core bats-assert bats-file bats-support
#
# Run all tests:
#   bats ./tests/test.bats
#
# Skip the "install from release" test (useful before tagging a release):
#   bats ./tests/test.bats --filter-tags '!release'
#
# Verbose:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=kevinquillen/ddev-neo4j

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"

  # Scaffold a minimal Drupal 11 project so the Drupal post-install
  # branch in install.yaml is exercised. We only need the directory
  # layout — Composer/Drupal install isn't required for the add-on
  # itself to install and run.
  mkdir -p web/sites/default
  cat > web/sites/default/settings.php <<'PHP'
<?php
$databases = [];
$settings['hash_salt'] = 'test';
PHP

  run ddev config \
    --project-name="${PROJNAME}" \
    --project-tld=ddev.site \
    --project-type=drupal11 \
    --docroot=web
  assert_success

  run ddev start -y
  assert_success
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ -n "${TESTDIR:-}" ] && rm -rf "${TESTDIR}"
  fi
}

# Shared health checks. Called by both "install from directory" and
# "install from release" tests so we catch breakage in either path.
health_checks() {
  # Browser UI reachable through the DDEV router.
  run curl -sSI -o /dev/null -w '%{http_code}' "https://${PROJNAME}.ddev.site:7475/"
  assert_success
  # Neo4j Browser serves a 200 at /, sometimes 303 to /browser/.
  [[ "${output}" == "200" ]] || [[ "${output}" == "303" ]] || [[ "${output}" == "302" ]]

  # Bolt protocol reachable from the web container.
  run ddev exec "nc -zv neo4j 7687"
  assert_success

  # Drupal settings include is wired and the file is present.
  run ddev exec "test -f web/sites/default/settings.ddev.neo4j.php"
  assert_success
  run ddev exec "grep -q 'settings.ddev.neo4j.php' web/sites/default/settings.php"
  assert_success

  # PHP can read the credentials block.
  run ddev exec "php -r 'include \"web/sites/default/settings.ddev.neo4j.php\"; echo isset(\$settings[\"content_graph_neo4j\"][\"uri\"]) ? \$settings[\"content_graph_neo4j\"][\"uri\"] : \"missing\";'"
  assert_success
  assert_output --partial "bolt://neo4j:7687"

  # Named volumes were created with the project-scoped names.
  run docker volume ls --format '{{.Name}}'
  assert_success
  assert_output --partial "ddev-${PROJNAME}-neo4j-data"
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "data persists across ddev restart" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  # Wait for Neo4j to accept Bolt queries (plugin install can take
  # 30+ seconds on first boot).
  local i=0
  until ddev exec "cypher-shell -a bolt://neo4j:7687 -u neo4j -p ddevpassword 'RETURN 1' >/dev/null 2>&1"; do
    i=$((i + 1))
    [ "${i}" -gt 30 ] && { echo "Neo4j never became reachable" >&3; return 1; }
    sleep 2
  done

  run ddev exec "cypher-shell -a bolt://neo4j:7687 -u neo4j -p ddevpassword 'CREATE (:DdevAddonTest {id: 1})'"
  assert_success

  run ddev restart -y
  assert_success

  # Re-check Bolt comes back after restart.
  i=0
  until ddev exec "cypher-shell -a bolt://neo4j:7687 -u neo4j -p ddevpassword 'RETURN 1' >/dev/null 2>&1"; do
    i=$((i + 1))
    [ "${i}" -gt 30 ] && { echo "Neo4j never came back after restart" >&3; return 1; }
    sleep 2
  done

  run ddev exec "cypher-shell -a bolt://neo4j:7687 -u neo4j -p ddevpassword 'MATCH (n:DdevAddonTest) RETURN count(n) AS c'"
  assert_success
  assert_output --partial "1"
}

@test "removal cleans up files and volumes" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  # Confirm the volume exists before removal.
  run docker volume ls --format '{{.Name}}'
  assert_output --partial "ddev-${PROJNAME}-neo4j-data"

  run ddev add-on remove neo4j
  assert_success

  # Drupal settings include is stripped.
  run ddev exec "test ! -f web/sites/default/settings.ddev.neo4j.php"
  assert_success
  run bash -c "! grep -q 'settings.ddev.neo4j.php' '${TESTDIR}/web/sites/default/settings.php'"
  assert_success

  # docker-compose file is removed from .ddev/.
  refute_file_exist "${TESTDIR}/.ddev/docker-compose.neo4j.yaml"

  # Named volumes are gone.
  run docker volume ls --format '{{.Name}}'
  refute_output --partial "ddev-${PROJNAME}-neo4j-data"
  refute_output --partial "ddev-${PROJNAME}-neo4j-logs"
  refute_output --partial "ddev-${PROJNAME}-neo4j-plugins"
}

@test "settings.php include is skipped for non-Drupal projects" {
  set -eu -o pipefail
  # Reconfigure as a generic PHP project before installing the add-on.
  run ddev config --project-type=php --docroot=web
  assert_success
  run ddev restart -y
  assert_success

  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  # The add-on must still install successfully and the service still
  # works — only the Drupal-specific wiring should be skipped.
  run curl -sSI -o /dev/null -w '%{http_code}' "https://${PROJNAME}.ddev.site:7475/"
  assert_success
  [[ "${output}" == "200" ]] || [[ "${output}" == "303" ]] || [[ "${output}" == "302" ]]

  # No settings.ddev.neo4j.php should have been copied into sites/default.
  refute_file_exist "${TESTDIR}/web/sites/default/settings.ddev.neo4j.php"
}
