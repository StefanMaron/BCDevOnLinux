#!/bin/bash

# BC Artifact URL Helper Script
# This script helps you find and set BC artifact URLs

echo "BC Artifact URL Helper"
echo "======================"
echo

# Check if PowerShell is available
if ! command -v pwsh &> /dev/null; then
    echo "PowerShell (pwsh) is required but not installed."
    echo "Please install PowerShell Core first."
    exit 1
fi

# Function to get artifact URL using PowerShell
get_artifact_url() {
    local type=$1
    local version=$2
    local country=$3
    local select=$4

    pwsh -Command "
        if (-not (Get-Module -ListAvailable -Name BcContainerHelper)) {
            Write-Host 'Installing BcContainerHelper module...'
            Install-Module -Name BcContainerHelper -Force -Scope CurrentUser
        }
        Import-Module BcContainerHelper -Force -DisableNameChecking

        try {
            if ('$select' -eq 'latest') {
                \$url = Get-BcArtifactUrl -type '$type' -country '$country' -select Latest
            } elseif ('$version' -ne 'latest') {
                \$url = Get-BcArtifactUrl -type '$type' -version '$version' -country '$country'
            } else {
                \$url = Get-BcArtifactUrl -type '$type' -country '$country'
            }
            Write-Host \$url
        } catch {
            Write-Error \"Failed to get artifact URL: \$_\"
            exit 1
        }
    "
}

# Interactive mode
echo "Available options:"
echo "1. Latest Sandbox (W1 - Global)"
echo "2. Latest Sandbox (US)"
echo "3. Latest OnPrem (W1 - Global)"
echo "4. Specific version"
echo "5. Custom PowerShell command"
echo "6. Exit"
echo

read -p "Select an option (1-6): " choice

case $choice in
    1)
        echo "Getting latest sandbox W1 URL..."
        url=$(get_artifact_url "Sandbox" "latest" "w1" "latest")
        ;;
    2)
        echo "Getting latest sandbox US URL..."
        url=$(get_artifact_url "Sandbox" "latest" "us" "latest")
        ;;
    3)
        echo "Getting latest OnPrem W1 URL..."
        url=$(get_artifact_url "OnPrem" "latest" "w1" "latest")
        ;;
    4)
        read -p "Enter version (e.g., 25, 26, 27): " version
        read -p "Enter country code (e.g., w1, us, dk): " country
        read -p "Enter type (Sandbox/OnPrem): " type
        echo "Getting $type $version $country URL..."
        url=$(get_artifact_url "$type" "$version" "$country" "")
        ;;
    5)
        echo "Enter your custom PowerShell command (e.g., Get-BcArtifactUrl -type Sandbox -version 25 -country us):"
        read -p "> " custom_command
        url=$(pwsh -Command "
            if (-not (Get-Module -ListAvailable -Name BcContainerHelper)) {
                Install-Module -Name BcContainerHelper -Force -Scope CurrentUser
            }
            Import-Module BcContainerHelper -Force -DisableNameChecking
            $custom_command
        ")
        ;;
    6)
        echo "Goodbye!"
        exit 0
        ;;
    *)
        echo "Invalid option selected."
        exit 1
        ;;
esac

if [ -n "$url" ] && [ "$url" != "" ]; then
    echo
    echo "Artifact URL found:"
    echo "=================="
    echo "$url"
    echo
    echo "To use this URL with docker-compose:"
    echo "1. Create a .env file in your project directory"
    echo "2. Add the following line to your .env file:"
    echo "   BC_ARTIFACT_URL=$url"
    echo "3. Run: docker-compose up --build"
    echo

    read -p "Would you like to create/update the .env file automatically? (y/n): " create_env

    if [ "$create_env" = "y" ] || [ "$create_env" = "Y" ]; then
        if [ -f ".env" ]; then
            # Update existing .env file
            if grep -q "^BC_ARTIFACT_URL=" .env; then
                sed -i "s|^BC_ARTIFACT_URL=.*|BC_ARTIFACT_URL=$url|" .env
                echo "Updated existing .env file with new BC_ARTIFACT_URL"
            else
                echo "BC_ARTIFACT_URL=$url" >> .env
                echo "Added BC_ARTIFACT_URL to existing .env file"
            fi
        else
            # Create new .env file
            echo "# BC Dev on Linux Environment Variables" > .env
            echo "SA_PASSWORD=YourStrongPassword123!" >> .env
            echo "BC_ARTIFACT_URL=$url" >> .env
            echo "Created new .env file with BC_ARTIFACT_URL"
        fi
        echo "You can now run: docker-compose up --build"
    fi
else
    echo "Failed to get artifact URL. Please check your input and try again."
    exit 1
fi
