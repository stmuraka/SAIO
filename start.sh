#!/bin/bash

# This script is executed when the Docker container is started
# This script will initialize the storage device for Swift and construct the rings.
# Once the rings are constructed, it will run through a series of tests that may take an upwards of 15-20 minutes.
# If you want to skip these tests, you can set the environment variable SKIP_TESTS=true

set -e

USER=$(whoami)

# Check for SKIP_TESTS variable, if not set to 'false'
SKIP_TESTS=${SKIP_TESTS:-"false"}

function formatTime() {
	t=${1}
	th=$(( t / 3600 ))
	tm=$(( (t / 60) % 60 ))
	ts=$(( t % 60 ))
	printf "%d:%02d:%02d" ${th} ${tm} ${ts}
}

echo "NOTE: Please wait approximately 10 minutes for Swift initialization and tests to complete"
echo ""

echo "Initializing Swift All-In-One"
echo ""

# Start timer
time_start=$(date '+%s')

# Using a loopback device for storage
echo "Creating loopback device of 1GB"
sudo truncate -s 1GB ${SAIO_BLOCK_DEVICE}
sudo mkfs.xfs -f ${SAIO_BLOCK_DEVICE}
echo ""

# Edit /etc/fstab and add:
echo "Updating /etc/fstab"
echo "${SAIO_BLOCK_DEVICE} /mnt/sdb1 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0"  | sudo tee --append /etc/fstab
echo ""

# Create the mount point and the individualized links:
echo "Create the mount point and the individualized links"
sudo mkdir -p /mnt/sdb1
sudo mount /mnt/sdb1
sudo mkdir -p /mnt/sdb1/1 /mnt/sdb1/2 /mnt/sdb1/3 /mnt/sdb1/4
sudo chown ${USER}:${USER} /mnt/sdb1/*
for x in {1..4}; do
    sudo ln -s /mnt/sdb1/$x /srv/$x
done
sudo mkdir -p /srv/1/node/sdb1 /srv/1/node/sdb5 \
         /srv/2/node/sdb2 /srv/2/node/sdb6 \
         /srv/3/node/sdb3 /srv/3/node/sdb7 \
         /srv/4/node/sdb4 /srv/4/node/sdb8 \
         /var/run/swift
sudo chown -R ${USER}:${USER} /var/run/swift
for x in {1..4}; do
    sudo chown -R ${USER}:${USER} /srv/$x/
done
echo ""

echo "Starting rsync, memcached, and rsyslog services"
## Start rsync
#service rsync restart
sudo /etc/init.d/rsync start

## Start memcached
sudo /etc/init.d/memcached start

## Restart rsyslog
sudo /etc/init.d/rsyslog restart
echo ""

## Construct the initial rings using the provided script ##
echo "---------------------------------------------------"
echo "Constructing rings..."
echo "---------------------------------------------------"
remakerings
echo "done"
echo ""

if [ "${SKIP_TESTS,,}" != "true" ]; then
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
fi

# Start the "main" Swift daemon processes (proxy, account, container, and object):
echo "---------------------------------------------------"
echo "Starting Swift daemon"
echo "---------------------------------------------------"
startmain
echo ""

if [ "${SKIP_TESTS,,}" != "true" ]; then
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

fi

# End timer
time_end=$(date '+%s')

echo ""
echo "---------------------------------------------------"
echo "Swift SAIO ready"
echo "Initialization time took: $(formatTime $(( time_end - time_start )))"
echo "---------------------------------------------------"
echo ""

# keep swift running
echo "---------------------------------------------------"
echo "Tailing logs..."
echo "---------------------------------------------------"
tail -f /var/log/swift/*
