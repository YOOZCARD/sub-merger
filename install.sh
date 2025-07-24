#!/bin/bash

# --- DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING ---

echo "Starting X-ui Traffic Sync Script..."

# Function to check and install dependencies
check_and_install_deps() {
    echo "Checking for required dependencies..."
    local deps=("curl" "jq")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo "All dependencies are installed."
        return 0
    fi

    echo "Missing dependencies: ${missing_deps[*]}"
    echo "Attempting to install missing dependencies..."

    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt update
        for dep in "${missing_deps[@]}"; do
            echo "Installing $dep..."
            sudo apt install -y "$dep"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to install $dep using apt. Please install it manually (sudo apt install -y $dep) and try again."
                exit 1
            fi
        done
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL/Fedora
        sudo yum check-update
        for dep in "${missing_deps[@]}"; do
            echo "Installing $dep..."
            sudo yum install -y "$dep"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to install $dep using yum. Please install it manually (sudo yum install -y $dep) and try again."
                exit 1
            fi
        done
    else
        echo "Warning: Unsupported operating system for automatic dependency installation."
        echo "Please install 'curl' and 'jq' manually and re-run the script."
        exit 1
    fi

    echo "Dependencies installed successfully."
}

# Run dependency check
check_and_install_deps

# Get X-ui Panel details from user
echo ""
echo "Please enter your X-ui Panel details:"
read -p "X-ui Panel Base URL (e.g., http://127.0.0.1:54321): " XUI_PANEL_BASE_URL
read -p "X-ui Panel Path URI (e.g., /admin/ or leave empty if none): " XUI_PANEL_PATH_URI
read -p "X-ui Username: " XUI_USERNAME
read -s -p "X-ui Password: " XUI_PASSWORD # -s for silent input (password)
echo "" # New line after password input for better formatting

# Validate and format XUI_PANEL_PATH_URI
# Ensure it starts and ends with a slash if not empty
if [ -n "$XUI_PANEL_PATH_URI" ]; then
    # Add leading slash if missing
    [[ "$XUI_PANEL_PATH_URI" != /* ]] && XUI_PANEL_PATH_URI="/$XUI_PANEL_PATH_URI"
    # Add trailing slash if missing
    [[ "$XUI_PANEL_PATH_URI" != */ ]] && XUI_PANEL_PATH_URI="${XUI_PANEL_PATH_URI}/"
fi

# Construct the full X-ui Panel URL
XUI_PANEL_URL="${XUI_PANEL_BASE_URL}${XUI_PANEL_PATH_URI}"

# Basic validation for Base URL
if [[ ! "$XUI_PANEL_BASE_URL" =~ ^https?:// ]]; then
    echo "Error: Invalid X-ui Panel Base URL format. It should start with http:// or https://."
    exit 1
fi

echo "Connecting to X-ui panel at $XUI_PANEL_URL..."

# 1. Get X-ui token
TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$XUI_USERNAME\",\"password\":\"$XUI_PASSWORD\"}" \
  "${XUI_PANEL_URL}login") # Append /login to the constructed URL

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.obj.token // empty') # Use jq for robust parsing

if [ -z "$TOKEN" ]; then
  echo "Error: Could not obtain X-ui token. Check your username, password, and panel URL/path."
  echo "Response from panel: $TOKEN_RESPONSE"
  exit 1
fi

echo "Successfully obtained X-ui token."

# 2. Get all inbounds
INBOUNDS_RESPONSE=$(curl -s -X GET \
  -H "Cookie: token=$TOKEN" \
  "${XUI_PANEL_URL}panel/api/inbounds/all") # Append /panel/api/inbounds/all

# Check for API response success
if ! echo "$INBOUNDS_RESPONSE" | jq -e '.success == true' > /dev/null; then
  echo "Error: Failed to retrieve inbounds data from X-ui panel."
  echo "Response from panel: $INBOUNDS_RESPONSE"
  exit 1
fi

INBOUNDS_DATA=$(echo "$INBOUNDS_RESPONSE" | jq -c '.obj[]')

if [ -z "$INBOUNDS_DATA" ]; then
  echo "No inbounds found or an issue occurred while parsing inbounds data."
  echo "Response from panel: $INBOUNDS_RESPONSE"
  exit 1
fi

echo "Successfully retrieved inbounds data."

# 3. Process inbounds to group by subscription_id and update traffic
declare -A subscription_id_traffic # Dictionary to store traffic for each subscription_id

# First pass: Determine the target traffic for each subscription_id
echo "Determining target traffic for each subscription ID..."
echo "$INBOUNDS_DATA" | while read -r inbound; do
  SETTINGS=$(echo "$inbound" | jq -r '.settings')
  TOTAL_TRAFFIC=$(echo "$inbound" | jq -r '.total') # Get total traffic in bytes

  # Parse clientMails to find subscription_id
  SUBSCRIPTION_ID=""
  # Safely check if 'clients' array exists and iterate
  if echo "$SETTINGS" | jq -e '.clients | length > 0' > /dev/null; then
    CLIENTS_ARRAY=$(echo "$SETTINGS" | jq -c '.clients[]')
    echo "$CLIENTS_ARRAY" | while read -r client; do
      if echo "$client" | jq -e 'has("subscriptionId")' > /dev/null; then
        SUBSCRIPTION_ID=$(echo "$client" | jq -r '.subscriptionId')
        break # Found subscriptionId, no need to check other clients for this inbound
      fi
    done
  fi

  if [ -n "$SUBSCRIPTION_ID" ]; then
    if [ -z "${subscription_id_traffic[$SUBSCRIPTION_ID]}" ]; then
      # First time seeing this subscription_id, set its target traffic
      subscription_id_traffic[$SUBSCRIPTION_ID]=$TOTAL_TRAFFIC
      echo "  Subscription ID: $SUBSCRIPTION_ID - Target Traffic: $(($TOTAL_TRAFFIC / 1024 / 1024)) MB" # Convert bytes to MB for display
    fi
  fi
done

# Second pass: Update total traffic for all inbounds with the same subscription_id
echo "Updating inbounds based on determined target traffic..."
echo "$INBOUNDS_DATA" | while read -r inbound; do
  INBOUND_ID=$(echo "$inbound" | jq -r '.id')
  TAG=$(echo "$inbound" | jq -r '.remark')
  CURRENT_TOTAL_TRAFFIC=$(echo "$inbound" | jq -r '.total')
  SETTINGS=$(echo "$inbound" | jq -r '.settings')

  SUBSCRIPTION_ID=""
  if echo "$SETTINGS" | jq -e '.clients | length > 0' > /dev/null; then
    CLIENTS_ARRAY=$(echo "$SETTINGS" | jq -c '.clients[]')
    echo "$CLIENTS_ARRAY" | while read -r client; do
      if echo "$client" | jq -e 'has("subscriptionId")' > /dev/null; then
        SUBSCRIPTION_ID=$(echo "$client" | jq -r '.subscriptionId')
        break
      fi
    done
  fi

  if [ -n "$SUBSCRIPTION_ID" ] && [ -n "${subscription_id_traffic[$SUBSCRIPTION_ID]}" ]; then
    TARGET_TRAFFIC=${subscription_id_traffic[$SUBSCRIPTION_ID]}

    if [ "$CURRENT_TOTAL_TRAFFIC" -ne "$TARGET_TRAFFIC" ]; then
      echo "  Updating inbound ID: $INBOUND_ID (Tag: $TAG, Subscription ID: $SUBSCRIPTION_ID)"
      echo "    Current Traffic: $(($CURRENT_TOTAL_TRAFFIC / 1024 / 1024)) MB, Target Traffic: $(($TARGET_TRAFFIC / 1024 / 1024)) MB"

      UPDATE_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Cookie: token=$TOKEN" \
        -d "{\"id\":$INBOUND_ID,\"remark\":\"$TAG\",\"total\":$TARGET_TRAFFIC}" \
        "${XUI_PANEL_URL}panel/api/inbounds/update") # Append /panel/api/inbounds/update

      if echo "$UPDATE_RESPONSE" | jq -e '.success == true' > /dev/null; then
        echo "    Successfully updated inbound ID: $INBOUND_ID"
      else
        echo "    Failed to update inbound ID: $INBOUND_ID"
        echo "    Response: $UPDATE_RESPONSE"
      fi
    else
      echo "  Inbound ID: $INBOUND_ID (Tag: $TAG, Subscription ID: $SUBSCRIPTION_ID) already has target traffic. No update needed."
    fi
  elif [ -z "$SUBSCRIPTION_ID" ]; then
    echo "  Inbound ID: $INBOUND_ID (Tag: $TAG) has no subscription_id. Skipping."
  fi
done < <(echo "$INBOUNDS_DATA") # Use process substitution for the second loop

echo "Script finished."
