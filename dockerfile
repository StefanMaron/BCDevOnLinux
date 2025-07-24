FROM ubuntu:22.04

# Essential environment variables following BC4Ubuntu approach
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=":0"

# Install base system packages following BC4Ubuntu methodology
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        winbind p7zip-full net-tools cabextract \
        wget curl gnupg2 software-properties-common ca-certificates \
        xvfb xauth \
        unzip && \
    # Enable i386 architecture for Wine
    dpkg --add-architecture i386 && \
    # Create apt keyrings directory
    mkdir -pm755 /etc/apt/keyrings && \
    # Add WineHQ repository following BC4Ubuntu approach
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu/ jammy main" > /etc/apt/sources.list.d/winehq.list && \
    apt-get update && \
    # Install wine-staging for better compatibility (as used in BC4Ubuntu)
    apt-get install -y --install-recommends winehq-staging && \
    # Add Microsoft repository for PowerShell
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg && \
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/microsoft-ubuntu-jammy-prod jammy main" > /etc/apt/sources.list.d/microsoft-prod.list && \
    apt-get update && \
    # Install PowerShell (needed for BcContainerHelper)
    apt-get install -y powershell && \
    # Clean up
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install winetricks following BC4Ubuntu approach
RUN cd /tmp && \
    wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x winetricks && \
    mv winetricks /usr/bin && \
    # Download completion script
    wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion && \
    mv winetricks.bash-completion /usr/share/bash-completion/completions/winetricks && \
    # Download man page
    wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.1 && \
    mv winetricks.1 /usr/share/man/man1/winetricks.1

# Create directories for BC artifacts and configuration
RUN mkdir -p /home/bcartifacts /home/bcserver/Keys

# Set shell to PowerShell for BC Container Helper installation
SHELL ["pwsh", "-Command"]

# Add build argument for BC artifact URL
ARG BC_ARTIFACT_URL=""

# Set as environment variable for use in RUN commands
ENV BC_ARTIFACT_URL=${BC_ARTIFACT_URL}

# Copy optimized download script
COPY download-bc-artifacts.ps1 /home/

# Download BC artifacts using optimized script
RUN Write-Host "BC_ARTIFACT_URL value: '$env:BC_ARTIFACT_URL'"; \
    if ([string]::IsNullOrEmpty($env:BC_ARTIFACT_URL) -or $env:BC_ARTIFACT_URL -eq '') { \
        Write-Host "No BC_ARTIFACT_URL provided, using default BC 26 Sandbox W1..."; \
        $artifactUrl = 'https://bcartifacts.azureedge.net/sandbox/26.0/w1'; \
    } else { \
        Write-Host "Using provided BC_ARTIFACT_URL: $env:BC_ARTIFACT_URL"; \
        $artifactUrl = $env:BC_ARTIFACT_URL; \
    }; \
    Write-Host "Final artifact URL: $artifactUrl"; \
    & /home/download-bc-artifacts.ps1 -ArtifactUrl $artifactUrl -IncludePlatform -DestinationPath '/home/bcartifacts' -Force

# Copy scripts and configuration files and make them executable
COPY *.ps1 /home/
COPY *.sh /home/
COPY CustomSettings.config /home/
RUN chmod +x /home/*.sh

# Expose BC ports
EXPOSE 7046 7047 7048 7049

# Set entrypoint
ENTRYPOINT ["/home/entrypoint.sh"]
