#!/usr/bin/env bash
# =============================================================
# build-and-publish.sh
# Build and publish the Windows Ansible Execution Environment
# Credentials are prompted securely at runtime (never stored)
# =============================================================
set -euo pipefail

# ----- Configuration (edit these) ----------------------------
EE_NAME="windows-ee"
EE_TAG="1.0.0"
TARGET_REGISTRY="aap-gateway.apps.ocp419.crucible.iisl.com"
AAP_REGISTRY="registry.redhat.io"
# -------------------------------------------------------------

FULL_IMAGE="${TARGET_REGISTRY}/${EE_NAME}:${EE_TAG}"

echo "========================================="
echo " Windows EE Builder"
echo " Image: ${FULL_IMAGE}"
echo "========================================="

# 1. Check prerequisites
for cmd in ansible-builder podman; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed. Please install it first."
    exit 1
  fi
done

# 2. Clean stale build context AND podman image cache
echo ""
echo "[0/4] Cleaning stale build context and cached image layers..."
rm -rf context/
podman rmi "${FULL_IMAGE}" 2>/dev/null || true
podman rmi "${TARGET_REGISTRY}/${EE_NAME}:latest" 2>/dev/null || true
podman image prune -f 2>/dev/null || true
echo "      Done."

# 3. Prompt securely for Red Hat registry credentials
echo ""
echo "[1/4] Red Hat Registry login (${AAP_REGISTRY})"
read -r -p "      Username: " AAP_REGISTRY_USER
read -r -s -p "      Password: " AAP_REGISTRY_PASS
echo ""

echo "      Authenticating..."
printf '%s' "${AAP_REGISTRY_PASS}" | podman login "${AAP_REGISTRY}" \
  --username "${AAP_REGISTRY_USER}" \
  --password-stdin \
  --tls-verify=true

unset AAP_REGISTRY_USER
unset AAP_REGISTRY_PASS

# 4. Log in to target registry
echo ""
echo "[2/4] Target registry login (${TARGET_REGISTRY})"
read -r -p "      Username: " TARGET_USER
read -r -s -p "      Password: " TARGET_PASS
echo ""

printf '%s' "${TARGET_PASS}" | podman login "${TARGET_REGISTRY}" \
  --username "${TARGET_USER}" \
  --password-stdin \
  --tls-verify=true

unset TARGET_USER
unset TARGET_PASS

# 5. Build the EE — no-cache to force all layers to rebuild
echo ""
echo "[3/4] Building EE with ansible-builder..."
ansible-builder build \
  --file execution-environment.yml \
  --tag "${FULL_IMAGE}" \
  --container-runtime podman \
  --verbosity 2 \
  --build-arg "PIP_CONSTRAINT=constraints.txt" \
  --build-arg "BUILDAH_ISOLATION=chroot" \
  -- --no-cache

echo "      Tagging as 'latest'..."
podman tag "${FULL_IMAGE}" "${TARGET_REGISTRY}/${EE_NAME}:latest"

# 6. Push to registry
echo ""
echo "[4/4] Pushing image to ${TARGET_REGISTRY}..."
podman push "${FULL_IMAGE}" \
  --tls-verify=true

podman push "${TARGET_REGISTRY}/${EE_NAME}:latest" \
  --tls-verify=true

echo ""
echo "✅ Done! Image available at:"
echo "   ${FULL_IMAGE}"
echo "   ${TARGET_REGISTRY}/${EE_NAME}:latest"