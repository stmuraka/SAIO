#!/bin/bash

# This script is executed when the Docker container is started
# This script will initialize the storage device for Swift and construct the rings.
# Once the rings are constructed, it will run through a series of tests that may take an upwards of 15-20 minutes.
# If you want to skip these tests, you can set the environment variable SKIP_TESTS=true

set -e

USER=$(whoami)

# Check for SKIP_TESTS variable, if not set to 'false'
SKIP_TESTS=${SKIP_TESTS:-"false"}
# Defines the file system type for the SAIO volume
FS_TYPE=${FS_TYPE:-"xfs"}

function formatTime() {
	t=${1}
	th=$(( t / 3600 ))
	tm=$(( (t / 60) % 60 ))
	ts=$(( t % 60 ))
	printf "%d:%02d:%02d" ${th} ${tm} ${ts}
}

# Check liberasurecode and recompile if tests dont' succeed
./liberasurecodeCheck.sh

# Initialize SAIO
echo ""
echo "==================================================="
echo "Initializing Swift All-In-One"
echo "==================================================="
echo ""

# Start timer
time_start=$(date '+%s')

# Using a loopback device for storage
echo "Creating loopback device of 1GB"
sudo truncate -s 1GB ${SAIO_BLOCK_DEVICE}
sudo mkfs.${FS_TYPE} -f ${SAIO_BLOCK_DEVICE}
echo ""

# Edit /etc/fstab and add:
echo "Updating /etc/fstab"
echo "${SAIO_BLOCK_DEVICE} /mnt/sdb1 ${FS_TYPE} loop,noatime,nodiratime,nobarrier,logbufs=8 0 0"  | sudo tee --append /etc/fstab
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

# Start the "main" Swift daemon processes (proxy, account, container, and object):
echo "---------------------------------------------------"
echo "Starting Swift daemon"
echo "---------------------------------------------------"
startmain
echo ""

# Run SAIO tests, skip if disabled
if [ "${SKIP_TESTS,,}" != "true" ]; then
	./runTests.sh || echo "Unable to run test script."
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
