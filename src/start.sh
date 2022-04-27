#!/usr/bin/env bash
set +x
set -o errexit
set -o pipefail
set -o nounset

# If there is some public key in keys folder
# then it copies its contain in authorized_keys file
if [ "$(ls -A /git-server/keys/)" ]; then
  cd /home/git
  cat /git-server/keys/*.pub > .ssh/authorized_keys
  chown -R git:git .ssh
  chmod 700 .ssh
  chmod -R 600 .ssh/*
fi

# Set permissions
if [ "$(ls -A /git-server/repos/)" ]; then
  cd /git-server/repos
  chown -R git:git .
  chmod -R ug+rwX .
  find . -type d -exec chmod g+s '{}' +
fi

# Set seeder user name
git config --global user.email "${GIT_USER_EMAIL:-root@gitsrv.git}"
git config --global user.name "${GIT_USER_NAME:-root}"

if [ -n "${GPG_KEYFILE-}" ]; then
  # Import the key
  gpg --import "${GPG_KEYFILE}"

  # Grab key ID and configure git
  key_id=$(gpg --no-tty --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ { print $5 }' | tail -1)
  git config --global user.signingkey "${key_id}"
fi

# Init repo and seed from a tar.gz link
REPO_DIR="/git-server/repos/${REPO}"

init_repo() {
  mkdir "${REPO_DIR}"
  cd "${REPO_DIR}"
  git init --shared=true

  if [ -n "${TAR_URL-}" ]; then
    while ! curl --verbose --location --fail "${TAR_URL}" | tar xz -C "./" --strip-components=1; do
      sleep 1
    done

    git add .
    gitcmd="git commit"
    if [ -n "${GPG_KEYFILE-}" ]; then
      gitcmd="$gitcmd -S"
    fi
    $gitcmd -m "init"
    git checkout -b dummy
  fi

  # If TAR_URL isn't set, check for an SSH_URL
  if [ -n "${SSH_URL-}" ]; then
    git clone "${SSH_URL}" .

    git add .
    gitcmd="git commit"
    if [ -n "${GPG_KEYFILE-}" ]; then
      gitcmd="$gitcmd -S"
    fi
    $gitcmd -m "init"
    git checkout -b dummy
  fi

  cd /git-server/repos
  chown -R git:git .
  chmod -R ug+rwX .
  find . -type d -exec chmod g+s '{}' +
}

if [ ! -d "${REPO_DIR}" ]; then
  init_repo
else
  # When download fails, this script restarts but we end up without any commits
  if [ -n "${SSH_URL}" ] | [ -n "${TAR_URL}" ] && [ "$(git rev-list --count HEAD --git-dir="${REPO_DIR}/.git")" -eq 0 ]; then
    rm -rf "${REPO_DIR}"
    init_repo
  fi
fi

# Link to home dir, this need to be done each time as this dir has the lifetime of the pod
ln -s "${REPO_DIR}" /home/git/

# -D flag avoids executing sshd as a daemon
/usr/sbin/sshd -D
