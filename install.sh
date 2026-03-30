#!/bin/bash
# Install mango-costs CLI
chmod +x "$(dirname "$0")/scripts/mango-costs"
sudo ln -sf "$(pwd)/scripts/mango-costs" /usr/local/bin/mango-costs
echo "✅ mango-costs installed to /usr/local/bin/mango-costs"
echo "Run: mango-costs status"
