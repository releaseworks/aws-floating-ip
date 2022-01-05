#!/bin/bash

# -- Optional config variables

# Netmask for the private IP address
NETMASK=$(ifconfig eth0|grep netmask|awk '{print $4}')

# Uncomment to enable debug output
# DEBUG=1

# The virtual / alias interface to use for the private IP
VIRTUAL_IF="eth0:0"

# -- End of configuration

if [[ "$1" == "" ]]; then
    echo >&2 "Usage: $0 <floating-ip>"
    exit 1
fi

FLOATING_IP=$1

# Check for prerequisites
command -v aws >/dev/null 2>&1 || { echo >&2 "Error: AWS CLI not found"; exit 1; }
command -v ping >/dev/null 2>&1 || { echo >&2 "Error: ping not found"; exit 1; }
command -v ifconfig >/dev/null 2>&1 || { echo >&2 "Error: ifconfig not found"; exit 1; }

# Main loop
while [ 1 ]; do
    # Sleep a random duration between 30 and 60 seconds to avoid race conditions
    sleep $[ ( $RANDOM % 30 )  + 30 ]s

    # Get the list of IP addresses on the primary ENI via the AWS instance metadata service
    LOCAL_IPS=$(curl -s http://169.254.169.254/2021-07-15/meta-data/network/interfaces/macs/$(cat /sys/class/net/eth0/address)/local-ipv4s)
    
    # Fail if local IPs cannot be found
    if [[ "$LOCAL_IPS" == "" ]]; then
        echo >&2 "Error: Local IPs not found. Am I running on an EC2 instance?"
        exit 1
    fi

    # Check if we have the FLOATING_IP, and continue to the next iteration if so
    if [[ "$LOCAL_IPS" == *"$FLOATING_IP"* ]]; then
        [[ -v DEBUG ]] && echo "$(date) I have the floating IP, skipping."
        continue
    else
        # If we don't have the FLOATING_IP, bring the VIRTUAL_IF down
        [[ -v DEBUG ]] && echo "$(date) I do not have the floating IP, bringing $VIRTUAL_IF down."
        ifconfig $VIRTUAL_IF down 2> /dev/null
    fi

    # Check if the FLOATING_IP is responding to ping, and continue to the next iteration if so
    if ping -c 1 $FLOATING_IP &> /dev/null; then
        [[ -v DEBUG ]] && echo "$(date) $FLOATING_IP is responding to ping, skipping."
        continue
    fi

    # The IP is not responding and we don't have it - let's attach it to ourselves
    # Get the primary network interface ID
    INTERFACE_ID=$(curl -s http://169.254.169.254/2021-07-15/meta-data/network/interfaces/macs/$(cat /sys/class/net/eth0/address)/interface-id)
    
    # Set the region for AWS CLI
    export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/2021-07-15/meta-data/placement/region)
    
    echo "$(date) Trying to attach $FLOATING_IP ..."
    if aws ec2 assign-private-ip-addresses --allow-reassignment --network-interface-id $INTERFACE_ID --private-ip-addresses $FLOATING_IP; then
        echo "$(date) Attached $FLOATING_IP on $INTERFACE_ID"

        ifconfig $VIRTUAL_IF $FLOATING_IP netmask $NETMASK

        # Sleep 30 seconds after attaching to wait for the metadata service to update
        sleep 30s
    else
        echo "$(date) Failed."

        ifconfig $VIRTUAL_IF down 2> /dev/null
    fi
done
