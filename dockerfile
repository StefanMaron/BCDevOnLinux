# Business Central on Linux using optimized base image
# Dramatically reduced from ~290 lines to ~60 lines
ARG BASE_IMAGE=stefanmaronbc/bc-wine-base:latest
FROM ${BASE_IMAGE}

# Set BC-specific environment variables
ARG BC_VERSION=26
ARG BC_COUNTRY=w1
ARG BC_TYPE=Sandbox

# Essential environment variables (inherits optimized Wine environment from base image)
ENV DEBIAN_FRONTEND=noninteractive \
    BCPORT=7046 \
    BCMANAGEMENTPORT=7045

# Set shell to PowerShell for BC operations (PowerShell already installed in base)
SHELL ["pwsh", "-Command"]

# Download BC artifacts (BC Container Helper already installed in base)
RUN Import-Module BcContainerHelper; \
    $artifactUrl = Get-BCartifactUrl -version $env:BC_VERSION -country $env:BC_COUNTRY -type $env:BC_TYPE; \
    $artifactPaths = Download-Artifacts $artifactUrl -includePlatform; \
    Write-Host "Artifact paths received:"; \
    $artifactPaths | ForEach-Object { Write-Host "  $_" }; \
    Write-Host "Contents of application artifacts ($($artifactPaths[0])):"; \
    Get-ChildItem "$($artifactPaths[0])" | ForEach-Object { Write-Host "  $($_.Name)" }; \
    Write-Host "Contents of platform artifacts ($($artifactPaths[1])):"; \
    Get-ChildItem "$($artifactPaths[1])" | ForEach-Object { Write-Host "  $($_.Name)" }; \
    Write-Host "Copying platform artifacts first from: $($artifactPaths[1])"; \
    Copy-Item -Path "$($artifactPaths[1])/*" -Destination "/home/bcartifacts" -Recurse -Force; \
    Write-Host "Copying application artifacts second from: $($artifactPaths[0])"; \
    Copy-Item -Path "$($artifactPaths[0])/*" -Destination "/home/bcartifacts" -Recurse -Force; \
    Write-Host "Final artifact structure:"; \
    Get-ChildItem "/home/bcartifacts" -Recurse -Depth 1 | Select-Object FullName | ForEach-Object { Write-Host "  $($_.FullName)" }

# Switch back to bash for remaining operations
SHELL ["/bin/bash", "-c"]

# Note: .NET 8 installation for BC v26 will happen at runtime in init-wine.sh
# This avoids Wine initialization issues during Docker build

# Copy scripts, tests, and configuration files
COPY scripts/ /home/scripts/
COPY tests/ /home/tests/
COPY config/CustomSettings.config /home/
RUN mkdir -p /home/config
COPY config/secret.key /home/config/
RUN mkdir -p /home/bcserver && cp /home/CustomSettings.config /home/bcserver/

# Copy BC console runner scripts to /home for easy access
COPY scripts/bc/run-bc-console.sh /home/run-bc-console.sh
COPY scripts/bc/run-bc-simple.sh /home/run-bc.sh

# Note: BC Server will be installed via MSI at runtime, not copied here
# The MSI installation will create the proper directory structure and registry entries

# Prepare encryption keys for later installation
RUN mkdir -p /home/config/Keys && \
    cp /home/config/secret.key /home/config/Keys/secret.key && \
    cp /home/config/secret.key /home/config/Keys/bc.key && \
    cp /home/config/secret.key /home/config/Keys/BusinessCentral260.key && \
    cp /home/config/secret.key /home/config/Keys/DynamicsNAV90.key

RUN find /home/scripts -name "*.sh" -exec chmod +x {} \; && \
    find /home/tests -name "*.sh" -exec chmod +x {} \; && \
    chmod +x /home/run-bc-console.sh /home/run-bc.sh

# Set up Wine environment for all shell sessions (base image provides optimized Wine environment)
RUN echo "" >> /root/.bashrc && \
    echo "# Wine environment for BC Server" >> /root/.bashrc && \
    echo "if [ -f /home/scripts/wine/wine-env.sh ]; then" >> /root/.bashrc && \
    echo "    source /home/scripts/wine/wine-env.sh >/dev/null 2>&1" >> /root/.bashrc && \
    echo "fi" >> /root/.bashrc

# Expose BC ports
EXPOSE 7046 7047 7048 7049

# Set entrypoint
ENTRYPOINT ["/home/scripts/docker/entrypoint.sh"]