#!/usr/bin/env bash

# This script will run tests against the Swift (SAIO) instance.
# The tests may take an upwards of 30 minutes to complete.

set -euo pipefail

echo "NOTE: Please wait 10-30 minutes for Swift initialization and tests to complete"
echo ""
## Verify the unit tests run:
echo "---------------------------------------------------"
echo "Running Swift Unit Tests..."
echo "---------------------------------------------------"
echo "NOTE: You may not see any output until the tests complete..."
# Need to su to ${USER} for running unit tests.
# For some reason, in the current environment, os.getgroups() does not return the user's primary group ID in the list
# This causes the unit tests to fail with the following error
#        FAIL: test_drop_privileges (test.unit.common.test_utils.TestUtils)
#       ----------------------------------------------------------------------
#       Traceback (most recent call last):
#         File "/home/swift/swift/test/unit/common/test_utils.py", line 2011, in test_drop_privileges
#           self.assertEqual(set(groups), set(os.getgroups()))
#       AssertionError: Items in the first set but not the second:
#       1000 - the user's group ID
sudo su - ${USER} -c "${HOME}/swift/.unittests"
echo "Swift Unit Tests complete"
echo ""

# Get an X-Storage-Url and X-Auth-Token:
echo "---------------------------------------------------"
echo "Testing Auth URL..."
echo "---------------------------------------------------"
curl -v -H 'X-Storage-User: test:tester' -H 'X-Storage-Pass: testing' http://127.0.0.1:8080/auth/v1.0
echo "Swift Auth URL test complete"
echo ""

# Check that you can GET account:
echo "---------------------------------------------------"
echo "Testing GET account info..."
echo "---------------------------------------------------"
auth_token=$(curl -sSLi -H 'X-Storage-User: test:tester' -H 'X-Storage-Pass: testing' http://127.0.0.1:8080/auth/v1.0 | grep 'X-Auth-Token:' | awk '{print $2}' | tr -d '\r')
storage_url=$(curl -sSLi -H 'X-Storage-User: test:tester' -H 'X-Storage-Pass: testing' http://127.0.0.1:8080/auth/v1.0 | grep 'X-Storage-Url:' | awk '{print $2}' | tr -d '\r')
curl -v -H "X-Auth-Token: ${auth_token}" ${storage_url}
echo "Swift GET account test complete"
echo ""

# Check that swift command provided by the python-swiftclient package works:
echo "---------------------------------------------------"
echo "Validating swift client..."
echo "---------------------------------------------------"
swift -A http://127.0.0.1:8080/auth/v1.0 -U test:tester -K testing stat
echo "Swift client test complete"
echo ""

# Verify the functional tests run:
# (Note: functional tests will first delete everything in the configured accounts.)
echo "---------------------------------------------------"
echo "Running Swift Function Tests..."
echo "---------------------------------------------------"
${HOME}/swift/.functests
echo "Swift Function test complete"
echo ""

# Verify the probe tests run:
echo "---------------------------------------------------"
echo "Running Swift Probe Tests..."
echo "---------------------------------------------------"
echo "NOTE: This test takes a few minutes to complete."
echo "NOTE: You may not see any output until the tests are done."
${HOME}/swift/.probetests
echo "Swift Probe test complete"
echo ""

# Start full environment
echo "---------------------------------------------------"
echo "Starting all swift services"
echo "---------------------------------------------------"
startmain
echo ""
