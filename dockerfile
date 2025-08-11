# Business Central on Linux using optimized base image
# Dramatically reduced from ~290 lines to ~60 lines using stefanmaronbc/bc-wine-base
FROM stefanmaronbc/bc-wine-base:latest

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
RUN $artifactUrl = Get-BCartifactUrl -version $env:BC_VERSION -country $env:BC_COUNTRY -type $env:BC_TYPE; \
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

# Install BC version-specific .NET components (only what's not in base image)
# Base image includes: Wine, .NET Framework 4.8, PowerShell, BC Container Helper, SQL tools
RUN cd /tmp && \
    # Install .NET 8 Desktop Runtime (version-specific for BC v26)
    echo "Installing .NET 8.0.18 Desktop Runtime..." && \
    wget -q "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.18/windowsdesktop-runtime-8.0.18-win-x64.exe" && \
    # Start Xvfb for .NET installation
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true && \
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX & \
    XVFB_PID=$! && \
    sleep 3 && \
    wine windowsdesktop-runtime-8.0.18-win-x64.exe /quiet /install /norestart && \
    rm -f windowsdesktop-runtime-8.0.18-win-x64.exe && \
    echo ".NET 8 Desktop Runtime installed" && \
    # Install ASP.NET Core 8.0 hosting bundle (version-specific for BC v26)
    echo "Installing ASP.NET Core 8.0.18 hosting bundle..." && \
    wget -q "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.18/dotnet-hosting-8.0.18-win.exe" && \
    wine dotnet-hosting-8.0.18-win.exe /quiet /install /norestart && \
    rm -f dotnet-hosting-8.0.18-win.exe && \
    echo "ASP.NET Core 8 hosting bundle installed" && \
    # Stop virtual display and clean up
    kill $XVFB_PID 2>/dev/null || true && \
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

# Copy scripts and configuration files
COPY scripts/ /home/scripts/
COPY config/CustomSettings.config /home/
RUN mkdir -p /home/config
COPY config/secret.key /home/config/
RUN mkdir -p /home/bcserver && cp /home/CustomSettings.config /home/bcserver/
RUN find /home/scripts -name "*.sh" -exec chmod +x {} \;

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