#!/bin/bash

# Ensure the script stops on error
set -e
echo $CI_WORKSPACE
echo $CI_PROJECT_DIR
# Define the Secrets.swift file path relative to the Git repository root
SECRETS_FILE="${CI_WORKSPACE}/Arkavo/ArkavoCreator/Secrets.swift"
echo $SECRETS_FILE
ls -l
# Ensure required environment variables are set
if [[ -z "${PATREON_CLIENT_ID}" || -z "${PATREON_CLIENT_SECRET}" ]]; then
  echo "Error: Required environment variables PATREON_CLIENT_ID or PATREON_CLIENT_SECRET are not set."
  exit 1
fi

# Create the Secrets.swift file with the necessary content
cat <<EOT > "$SECRETS_FILE"
// Do not commit this file.
// This file is auto-generated during CI/CD.

struct Secrets {
    static let patreonClientId = "${PATREON_CLIENT_ID}"
    static let patreonClientSecret = "${PATREON_CLIENT_SECRET}"
}
EOT

echo "Secrets.swift has been successfully generated at $SECRETS_FILE"
