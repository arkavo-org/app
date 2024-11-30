#!/bin/bash

# Ensure the script stops on error
set -e

# Define the Secrets.swift file path relative to the Git repository root
SECRETS_FILE="../Arkavo/Secrets.swift"

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
