### How to create a UDP tunnel with socat

#### Prerequisites
* To test the overlay network we need 2 VMs that are mutually reachable using predefined UDP port.
This is important since cloud providers usually restrict the ports that can be accessed exterior.
* The center tool is socat which will be used to embed the IP (v4 or v6) packets received on the 
TUNnel interface (L3 network layer) in UDP IPv4 datagrams as data. 
The receiving VM, using the same tool will unpack the UDP IPv4 datagrams and forward the 
embedded IP packet to the TUN interface.
* Root privileges on both VMs for creating TUN interfaces; on Linux root requires `CAP_NET_ADMIN` capability

#### Setup
* For VM_A:
```
export TUNNEL_IP=172.30.0.1   ; echo set tun interface IP to $TUNNEL_IP
export TO_VM_IP=192.168.1.103 ; echo send UDP datagrams to remote VM IP $TO_VM_IP
export VM_IP=192.168.1.114    ; echo listen for UDP datagrams on current VM IP $VM_IP
export UDP_PORT=9090          ; echo accept packets on UDP port $UDP_PORT 
```
* For VM_B:
```
export TUNNEL_IP=172.30.0.2   ; echo set tun interface IP to $TUNNEL_IP
export TO_VM_IP=192.168.1.114 ; echo send UDP datagrams to remote VM IP $TO_VM_IP
export VM_IP=192.168.1.103    ; echo listen for UDP datagrams on current VM IP $VM_IP
export UDP_PORT=9090          ; echo accept packets on UDP port $UDP_PORT 
```
Update the above envars so `VM_IP` is the IP of the interface on current VM that can reach the remote VM IP `TO_VM_IP`.

Note, that we assume the two tunnel interfaces to be on the same network `172.30.0.0/16`. This is how overlay networks operate on multiple nodes.

#### Running socat
As previously said must run socat relay as root on each VM:
```
sudo socat -ddd TUN:$TUNNEL_IP/16,iff-up UDP-DATAGRAM:$TO_VM_IP:$UDP_PORT,bind=$VM_IP:$UDP_PORT:$UDP_PORT &
```
Note the `-ddd` is optional and in this example it is used for debugging.
Also, note that we launch the process in the background in order to check what is beeing sent/received.

Suppose we ping with a single message the tun interface `172.30.0.1` on VM_B from VM_A:
```
$ ping 172.30.0.1 -c 1
```
We will get something like this:
```
PING 172.30.0.1 (172.30.0.1) 56(84) bytes of data.
socat[464260] N local address: AF=2 192.168.1.103:9090
socat[464260] I transferred 88 bytes from 5 to 7
socat[464260] I permitting packet from AF=2 192.168.1.114:9090
socat[464260] N received packet with 88 bytes from AF=2 192.168.1.114:9090
socat[464260] I transferred 88 bytes from 7 to 5
64 bytes from 172.30.0.1: icmp_seq=1 ttl=64 time=1.93 ms

--- 172.30.0.1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 1.930/1.930/1.930/0.000 ms```
```

#### Troubleshooting
* The error *E unknown device/address "TUN"* means that this version socat doesn't support
tunnel interfaces on current system
