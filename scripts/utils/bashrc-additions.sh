#!/bin/bash
# Add Wine environment to bashrc

echo "" >> /root/.bashrc
echo "# Wine environment for BC Server" >> /root/.bashrc
echo "if [ -f /home/wine-env.sh ]; then" >> /root/.bashrc
echo "    source /home/wine-env.sh" >> /root/.bashrc
echo "fi" >> /root/.bashrc