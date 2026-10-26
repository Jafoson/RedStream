"""Approves every pending web-app access request (CI only: the iOS UI test
can't run the server CLI itself, so this loop does it).

    HOME=<server HOME> python ios/ci/auto_approve.py
"""

import subprocess
import time

seen = set()
while True:
    listing = subprocess.run(["aniworld", "--web-requests"], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        parts = line.split()
        if parts and parts[0].isdigit() and "pending" in parts and parts[0] not in seen:
            seen.add(parts[0])
            print(subprocess.run(["aniworld", "--web-approve", parts[0]], capture_output=True, text=True).stdout, flush=True)
    time.sleep(2)
