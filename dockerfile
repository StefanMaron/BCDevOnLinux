# Use the BCOnLinuxBase image that includes Wine, PowerShell, BC Container Helper, and all dependencies
FROM stefanmaronbc/bc-wine-base:latest

# Set BC-specific environment variables
ENV BCPORT=7046 \
    BCMANAGEMENTPORT=7045 \
    BCSOAPPORT=7047 \
    BCODATAPORT=7048 \
    BCDEVPORT=7049 \
    WINEPREFIX=/opt/wine-prefix \
    BC_AUTO_REGENERATE_KEY=true

# Download BC artifacts (configurable version)
ARG BC_VERSION=26
ARG BC_COUNTRY=w1
ARG BC_TYPE=Sandbox

# Set environment variables from build args so they're available in PowerShell
ENV BC_VERSION=${BC_VERSION}
ENV BC_COUNTRY=${BC_COUNTRY}
ENV BC_TYPE=${BC_TYPE}

# Set shell to PowerShell for BC artifacts download
SHELL ["pwsh", "-Command"]

# Download and install BC artifacts
RUN Import-Module BcContainerHelper; \
    $artifactUrl = Get-BCArtifactUrl -version $env:BC_VERSION -country $env:BC_COUNTRY -type $env:BC_TYPE; \
    Write-Host "Downloading BC artifacts from: $artifactUrl"; \
    $artifactPaths = Download-Artifacts $artifactUrl -includePlatform; \
    Write-Host "Artifact paths received:"; \
    $artifactPaths | ForEach-Object { Write-Host "  $_" }; \
    Write-Host "Copying platform artifacts first from: $($artifactPaths[1])"; \
    Copy-Item -Path "$($artifactPaths[1])/*" -Destination "/home/bcartifacts" -Recurse -Force; \
    Write-Host "Copying application artifacts second from: $($artifactPaths[0])"; \
    Copy-Item -Path "$($artifactPaths[0])/*" -Destination "/home/bcartifacts" -Recurse -Force; \
    Write-Host "BC artifact structure:"; \
    Get-ChildItem "/home/bcartifacts" -Recurse -Depth 1 | Select-Object FullName | ForEach-Object { Write-Host "  $($_.FullName)" }

# Switch back to bash
SHELL ["/bin/bash", "-c"]

# Copy BC configuration and scripts
COPY *.ps1 /home/
COPY *.sh /home/
COPY bc-encryption-functions.sh /home/
COPY CustomSettings.config /home/
RUN chmod +x /home/*.sh

# Expose BC ports
EXPOSE 7046 7047 7048 7049

# Set entrypoint
ENTRYPOINT ["/home/entrypoint.sh"]