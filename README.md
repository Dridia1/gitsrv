# gitsrv

[![build](https://github.com/fluxcd/gitsrv/workflows/build/badge.svg)](https://github.com/fluxcd/gitsrv/actions)
[![e2e](https://github.com/fluxcd/gitsrv/workflows/e2e/badge.svg)](https://github.com/fluxcd/gitsrv/actions)
[![release](https://github.com/fluxcd/gitsrv/workflows/release/badge.svg)](https://github.com/fluxcd/gitsrv/actions)

SSH only Git Server used to host a git repository initialized from a tar.gz URL.

## Usage

Generate a SSH key:

```bash
gen_dir=$(mktemp -d)
ssh-keygen -t rsa -N "" -f "$gen_dir/id_rsa"

kubectl create secret generic ssh-key \
  --from-file="$gen_dir/id_rsa" \
  --from-file="$gen_dir/id_rsa.pub"
```

Export a GPG key (optional):

```bash
gpg --export-secret-keys key_id | \
kubectl create secret generic gpg-signing-key \
  --from-file=gitsrv.asc=/dev/stdin
```

Create a kustomization and set `TAR_URL`:

```bash
cat > kustomization.yaml <<EOF
bases:
  - github.com/fluxcd/gitsrv/deploy
patches:
- target:
    kind: Deployment
    name: gitsrv
  patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: gitsrv
    spec:
      template:
        spec:
          containers:
          - name: gitsrv
          env:
            - name: REPO
              value: "cluster.git"
            - name: TAR_URL
              value: "https://github.com/fluxcd/flux-get-started/archive/master.tar.gz"
            - name: GPG_KEYFILE
              value: /git-server/gpg/gitsrv.asc
          volumeMounts:
            - mountPath: /git-server/gpg
              name: git-gpg-keys
      volumes:
        - name: git-gpg-keys
          secret:
            secretName: gpg-signing-key
EOF
```

Create a kustomization and set `SSL_URL`:

```bash
cat > kustomization.yaml <<EOF
bases:
  - github.com/fluxcd/gitsrv/deploy
patches:
- target:
    kind: Deployment
    name: gitsrv
  patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: gitsrv
    spec:
      template:
        spec:
          containers:
          - name: gitsrv
            env:
            - name: REPO
              value: "cluster.git"
            - name: SSH_URL
              value: "git@gitlab.com:someUsername/cluster.git"

EOF
```

Deploy the git server:

```bash
kustomize build . | kubectl apply -f -
```

Clone the repo from another pod that has the same `ssh-key` secret mounted:

```bash
git clone -b master ssh://git@gitsrv/~/cluster.git
```

## Release

To make a gitsrv release do:
* create a branch `prepare-v1.0.0`
* bump the version in [deploy/kustomization.yaml](deploy/kustomization.yaml)
* merge the PR and pull master locally
* run `make release`
* the [release workflow](.github/workflows/release.yml)
    will create a GitHub release, push the image to Docker Hub and upload the SSH fingerprint to the release assets
