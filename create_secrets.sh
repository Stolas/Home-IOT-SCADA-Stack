#!/bin/bash

# --- Configuration ---
ENV_EXAMPLE_FILE="secrets.env-example"
ENV_FILE="secrets.env"
RANDOM_LENGTH=64

# Function to generate a secure random string using /dev/urandom
# Generates alphanumeric characters only, 64 characters long.
generate_random_string() {
    # tr -dc: delete characters that are NOT (a-zA-Z0-9)
    # </dev/urandom: reads random data from the kernel's entropy pool
    # head -c $RANDOM_LENGTH: takes the first 64 characters
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$RANDOM_LENGTH"
}

# --- Script Logic ---

if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
    echo "Error: Template file '$ENV_EXAMPLE_FILE' not found."
    exit 1
fi

if [ -f "$ENV_FILE" ]; then
    echo "The file '$ENV_FILE' already exists. No changes made."
    echo "Please delete or rename '$ENV_FILE' if you wish to regenerate it."
    exit 0
fi

echo "Creating secure '$ENV_FILE' from '$ENV_EXAMPLE_FILE'..."

# Use a temporary file for processing to ensure safe and atomic writing
TEMP_FILE=$(mktemp)

# Use sed to process the file and substitute placeholders
# We only substitute values that are clearly placeholders for passwords/tokens/keys.

sed -e "
    /^MQTT_PASSWORD=/c\MQTT_PASSWORD=$(generate_random_string)
    /^INFLUXDB_ADMIN_PASSWORD=/c\INFLUXDB_ADMIN_PASSWORD=$(generate_random_string)
    /^INFLUXDB_ADMIN_TOKEN=/c\INFLUXDB_ADMIN_TOKEN=$(generate_random_string)
    /^GRAFANA_ADMIN_PASSWORD=/c\GRAFANA_ADMIN_PASSWORD=$(generate_random_string)
    /^GRAFANA_SECRET_KEY=/c\GRAFANA_SECRET_KEY=$(generate_random_string)
    /^SMB_PASS=/c\SMB_PASS=$(generate_random_string)
    /^COMPREFACE_API_KEY=/c\COMPREFACE_API_KEY=$(generate_random_string)
    /^POSTGRES_PASSWORD=/c\POSTGRES_PASSWORD=$(generate_random_string)
" "$ENV_EXAMPLE_FILE" > "$TEMP_FILE"

# The 'c\' command in sed completely replaces the line with the specified string.
# This ensures that we don't accidentally leave any part of the placeholder in.

# Copy the securely modified content to the final .env file
mv "$TEMP_FILE" "$ENV_FILE"

echo "Success: '$ENV_FILE' has been created with new random secrets."
echo "CRITICAL: Remember to manually update 'ZIGBEE_DEVICE_PATH' with your adapter ID."

# Clean up the temporary file (in case mv failed for some reason)
rm -f "$TEMP_FILE"

exit 0
