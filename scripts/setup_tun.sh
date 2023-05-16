#!/bin/sh

IPV6P='3000::'
printf "Setup interface tun$1 for user $USER and IPv6: $IPV6P$2\n"

# Load the tun kernel module if not already loaded
modprobe tun

# Create the tunX interface for current user
ip tuntap add mode tun user $USER name tun$1

# Bring up the tun interface 
ip link set dev tun$1 up

# Assign a known IPV6 address for tunX
ip -6 address add $IPV6P/127 dev tun$1

# Add a route to the remote tun interface pair
ip -6 route add $IPV6P/127 dev tun$1

