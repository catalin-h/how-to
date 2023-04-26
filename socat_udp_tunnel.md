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

#### Why use a UDP channel
Using a TCP connection would be an overkill for a tunnel because it would require
more resources from kernel side than UDP. For eg. maintaining an active TCP
connection requires sending periodic SYN to avoid dropping the connection
from the other endpoint. With UDP packets are sent on demand. For connection
reliability is responsible the TCP socket opened on the TUN interface side.

Also, UDP doesn't the MSS (maximum segment size) option as TCP does.
This means no state needs to be kept and the IP layer is responsible for packet fragmentation. 

Offtopic, the IP layer uses the MTU Link layer property to split the packet in
fragments that can be accepted by the data-link layer.
The actual MTU value depends on the network interface.
Also, it can be computed using a mechanism called Path MTU discovery.
This mechanism is enabled by default in Linux kernel for IPv4 if the
`/proc/sys/net/ipv4/ip_no_pmtu_disc` is `0` (boolean value). Another way,
it is when the application uses a SOCK_STREAM socket and explicitly sets the
`IP_MTU_DISCOVER` or `IPV6_MTU_DISCOVER` socket options.
Settings the right MTU is important since with IPv6, the routers will not
fragment packets bigger than their MTU and it is the sender responsability
to properly split the packets into fragments. In IPv6, the minimum link MTU
is 1280 octets and for IPV4 is 576 octets.
For non-SOCK_STREAM sockets like, the Linux application can use several strategies
by allowing the kernel to do path MTU dicovery or not and by handling or not the
datagram fragmentation:
>By default, Linux UDP does path MTU (Maximum Transmission Unit)
discovery.  This means the kernel will keep track of the MTU to a
specific target IP address and return EMSGSIZE when a UDP packet
write exceeds it.  When this happens, the application should
decrease the packet size.  Path MTU discovery can be also turned
off using the IP_MTU_DISCOVER socket option or the
/proc/sys/net/ipv4/ip_no_pmtu_disc file; see ip(7) for details.
When turned off, UDP will fragment outgoing UDP packets that
exceed the interface MTU.  However, disabling it is not
recommended for performance and reliability reasons.

See programming references for [udp](https://www.man7.org/linux/man-pages/man7/udp.7.html) and 
[ip](https://www.man7.org/linux/man-pages/man7/ip.7.html).

#### Troubleshooting
* The error *E unknown device/address "TUN"* means that this version socat doesn't support
tunnel interfaces on current system

#### References
* [Overlay Network](https://github.com/kristenjacobs/container-networking/tree/master/4-overlay-network)
* [Building TUN based virtual networks with socat](https://stuff.mit.edu/afs/sipb/machine/penguin-lust/src/socat-1.7.1.2/doc/socat-tun.html)
* [Path MTU discovery in practice](https://blog.cloudflare.com/path-mtu-discovery-in-practice/)
* [What is maximum segment size (MSS)](https://www.cloudflare.com/learning/network-layer/what-is-mss/)
* [What is MTU?](https://www.cloudflare.com/learning/network-layer/what-is-mtu/)
* [Linux IPv4 protocol implementation](https://www.man7.org/linux/man-pages/man7/ip.7.html)
* [Linux IPv6 protocol implementation](https://www.man7.org/linux/man-pages/man7/ipv6.7.html)
* [User Datagram Protocol for IPv4](https://www.man7.org/linux/man-pages/man7/udp.7.html)
