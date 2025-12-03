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

# Note: .NET 8 installation for BC v26 will happen at runtime in init-wine.sh
# This avoids Wine initialization issues during Docker build

# Copy scripts, tests, and configuration files
COPY scripts/ /home/scripts/
COPY tests/ /home/tests/
COPY config/CustomSettings.config /home/
RUN mkdir -p /home/config
COPY config/secret.key /home/config/

# Copy BC console runner scripts to /home for easy access
COPY scripts/bc/run-bc-console.sh /home/run-bc-console.sh
COPY scripts/bc/run-bc-simple.sh /home/run-bc.sh

# Note: BC Server will be installed via MSI at runtime, not copied here
# The MSI installation will create the proper directory structure and registry entries

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
EXPOSE 7045 7046 7047 7048 7049

# Set entrypoint
ENTRYPOINT ["/home/scripts/docker/entrypoint.sh"]