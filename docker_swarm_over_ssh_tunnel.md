### How to enable Docker swarm node communication over ssh tunnel
Docker overlay networks can expand over machines on different geographic zones.
Also, in order to add different nodes into a Docker swarm the machines need to
open several TCP/UDP ports for different planes:
* 2377/tcp docker swarm cluster management communication (management plane)
* 7946/tcp and 7946/udp SWIM-based gossip communication among nodes and container network discovery (control plane)
* 4789/udp for the VXLAN overlay network traffic (data plane)

This can pose some problems when connecting machines on the cloud as due to security
administrators choose to open a very restricted number of TCP ports. Also, some
of the nodes can't be reachable from exterior as they lack a _public_ IP.
If they have a public IP but they are on different cloud environment then we need to
replicate the same port setup on each environment.
If we know that ssh port 22 is always open we can allow swarm nodes communication using
a tunnel.
In the next scenario we will have one remote VM with a public IP running in cloud environment
and one VM running on local network.

<a name="Prerequisites"></a>
#### Prerequisites
* Linux Kernel min. 5.x
* Docker version 23
* If one of the machines runs in a cloud environment then it needs to have a public IP

#### Setup the ssh tunnel
For simplicity we assume there are two machines:
* docker01: this machine initiates the ssh connection and configures the tunnel
* docker02: this will act as the remote machine and it is required to have an IP address
that is reachable from docker01

Since we use the `ssh` option `-w` that requires a `tunnel` interface on each machine
we have the possibility to either create these interfaces in advance or configure them
after the `sshd` daemon establishes the connection. As these interfaces can have statically
assigned IP addresses we can configure them before the connection which is basically a
point to point one. The following [script](./scripts/setup_tun.sh) should be run as `root`
on `docker01` as `./setup_tun.sh 0 0` and on `docker02` `./setup_tun.sh 0 0`:
```
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
```
Note:
* the first parameter represents the tun interface number; if the machine for e.g. already has a `tun0` then the first argument should be the next available interface id
* the first parameter is important as it will be passed to `ssh` as `-w`<local tun number>:<remote tun number>
* we use an IPv6 address to avoid any IP collision with existing network interfaces; this IP will be used to initialize the docker swarm manager and worker

In order for the `sshd` process to start forward packets over the tunnel , on `docker02` must
set the `PermitTunnel` option from `sshd_config` to `point-to-point` or `yes`.
To show the current configuration for `sshd` daemon run:
```
sudo sshd -T
```
If this option is not enabled the client on `docker01` will get the error
`Server has rejected tunnel device forwarding` when debug log is enabled (with option `-vv`).

To create the ssh tunnel run on `docker01` the command as `root`:
```
ssh -oTunnel=point-to-point \
	-oServerAliveInterval=10 \
	-oTCPKeepAlive=yes \
	-oControlMaster=yes \
	-S ~/ssh_tunnel1 \
	-i ~/.ssh/key \
	-f \
	-w 0:0 \
	ubuntu@cloud \
	true
```
Parameters:
* `-oTunnel` :
>Request tun(4) device forwarding between the client and the server
* `-oServerAliveInterval=10` : 
>Sets a timeout interval of seconds after which if no data
has been received from the server, ssh(1) will send a message through the encrypted channel to request a response from the server
* `-oTCPKeepAlive=yes` : 
>Specifies whether the system should send TCP keepalive messages to the other side. 
If they are sent, death of the connection or crash of one of the machines will be properly noticed. 
However, this means that connections will die ifthe route is down temporarily, and some people find it annoying.
* `-oControlMaster=yes` : ssh will listen on control unix socket for commands;
this socket is useful to gracefully close the tunnel connection; otherwise
one must search for the pid of the background process and use `kill` to terminate
the ssh tunnel.
* `-S ~/ssh_tunnel1` : provides the path for the control socket.
* `-i ~/.ssh/key` : the user private key as we assume we use a ssh authorized key to authenticate o `docker02`.
* `-f` : the ssh process will fork to a new process in background.
* `-w 0:0` : use tun0 on both local and remote machines.
* `ubuntu@cloud` : the `authority` or the user@remote_server.
* `true` : if we use `-f` must have a command to run in the background; in this case we use the utility `true`.

For more details on check the [ssh_config manual](https://www.man7.org/linux/man-pages/man5/ssh_config.5.html)

To close the tunnel connection just run the command as `root`:
```
ssh -S /tmp/ssh_tunnel1 -O exit ubuntu@cloud 
```
If the command succeeds we can verify the connectivity:
```
docker01:~$ ping 3000::1 -c 1
PING 3000::1(3000::1) 56 data bytes
64 bytes from 3000::1: icmp_seq=1 ttl=64 time=72.4 ms

--- 3000::1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 72.400/72.400/72.400/0.000 ms
```
#### Enable swarm mode
To create a multi node Docker swarm first must create _manager_ node.
In our case let's make `docker01` the swarm manager by enabling the Docker swarm mode on this machine:
```
docker01:~$ sudo docker swarm init --advertise-addr 3000::0
Swarm initialized: current node (i72q9ij60tavr8g72stwnb24i) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-5p05em8ngji915v93fuzaaxghi25txq49pbzoeyan2dm17b3b8-6s0er8i4gp689ybt9rqu9t424 [3000::]:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```
Note:
* since the machine has several network interfaces we must ensure that we choose the right interface
* even if the `--advertise-addr` option accepts a interface name like `tun0` it's not enough since
there can be many IPs assigned to a single network interface so we must provide the IP that
the swarm _manager_ should listen for updates from other swarm nodes. If we try to pass
a multi-IP interface we would get an error:
`Error response from daemon: interface tun0 has more than one IPv6 address (3000:: and fe80::6a5a:3313:847:2de2)`
* as we will explain in the next section [working with overlay networks](#working_with_overlay_networks) the
IPv6 support still needs some work in swarm mode; this example shows only you can _reliable_ do with
the current IPv6 support

On the other machine `docker02` we need to join the swarm created by `docker01`:
```
docker02:~$ sudo docker swarm join --token SWMTKN-1-5p05em8ngji915v93fuzaaxghi25txq49pbzoeyan2dm17b3b8-6s0er8i4gp689ybt9rqu9t424 [3000::]:2377
This node joined a swarm as a worker. 
```

If we go back to the `manager` node we can list both nodes:
```
docker01:~$ sudo docker node ls
ID                            HOSTNAME   STATUS    AVAILABILITY   MANAGER STATUS   ENGINE VERSION
i72q9ij60tavr8g72stwnb24i *   docker01   Ready     Active         Leader           23.0.3
lf0z6z5pxblm69o0m2u4q24wi     docker02   Ready     Active                          23.0.3
```
As a side note, Docker allows into swarm nodes with different hardware architectures:
```
docker01:~$ sudo docker node inspect docker02 -f '{{ .Description.Platform.Architecture }}'
aarch64
docker01:~$ sudo docker node inspect docker01 -f '{{ .Description.Platform.Architecture }}'
x86_64
```
Lets try create a `global` mode service that will force each node run a container:
```
docker01:~$ sudo docker service create --name sleep_01 --mode global alpine:latest sleep 1d
lmce3jjcduurbslq05qh1ziua
overall progress: 2 out of 2 tasks
i72q9ij60tav: running   [==================================================>]
lf0z6z5pxblm: running   [==================================================>]
verify: Service converged
```
Since we specified `--mode global` both nodes get to run the `sleep` command:
```
docker01:~$ sudo docker service ps sleep_01
ID             NAME                                 IMAGE           NODE       DESIRED STATE   CURRENT STATE                ERROR     PORTS
jmo4l26rmmje   sleep_01.i72q9ij60tavr8g72stwnb24i   alpine:latest   docker01   Running         Running about a minute ago
uiiv3i7hahdt   sleep_01.lf0z6z5pxblm69o0m2u4q24wi   alpine:latest   docker02   Running         Running about a minute ago
```
If we go to `docker02` node and list the containers we see that there is indeed a single container running:
```
docker02:~$ sudo docker container ls
CONTAINER ID   IMAGE           COMMAND      CREATED         STATUS         PORTS     NAMES
638d25e5e49c   alpine:latest   "sleep 1d"   3 minutes ago   Up 3 minutes             sleep_01.lf0z6z5pxblm69o0m2u4q24wi.uiiv3i7hahdtgw66vvtne5rzl
```

<a name="working_with_overlay_networks"></a>
#### Working with overlay networks
The next example will test a more real scenario were a service uses a custom network.
This network will isolate the traffic between containers from other services and host network.
One benefit of this is that the custom network will have its own DNS service that will spawn on different nodes.
On Docker networks that spawn on different nodes or machines are called overlay and usually use VXLAN to achieve this.

Unfortunately the `overlay` driver doesn't fully support IPv6 and there are severals [bugs](#ipv6_swarm_overlay_issues)
that are still opened for the `moby` project on github.

The setup that we did earlier with nodes communicating to over IPv6 addresses must be redone but this time with IPv4 addresses.
To clean the previous setup each node must `leave` the swarm mode with:
```
$ sudo docker swarm leave --force
Node left the swarm
```

Before putting any node in swarm mode first we have to assign an IPv4 address to each `tun0` interface on both VMs:
* `docker01`
```
$ sudo ip address add 172.30.1.1/24 dev tun0
```
* `docker02`
```
$ sudo ip address add 172.30.1.2/24 dev tun0
```

Next, we should put the `docker01` back into swarm mode by advertising an IPv4 address:
```
sudo docker swarm init --advertise-addr 30.0.0.1
```

##### Create the overlay network
On the same node we create an `overlay` network with a custom subnet:
```
 sudo docker network create -d overlay --attachable --driver=overlay --subnet=172.30.1.0/24 sleep-big-net
```
Note:
* overlay network can be created only on manager swarm nodes
* the new network is not made available immediately in other nodes unless a container is _attached_ to it
* worker nodes can't create overlay networks
* the `--attachable` allows single containers to attach to the network and communicate with any container in that network regardless of the swarm node
* overlay networks provide an internal DNS so containers created with `--name <name>` can be found with the provided name

In order to delete the overlay network just run the `docker network rm`.
In a rare situations where this commands can fail to delete a network because Docker still has a reference of it in `task`:
```
$ sudo docker network rm -f sleep-overlay-net
Error response from daemon: rpc error: code = FailedPrecondition desc = network 11tmyyywlm60td96obhxobgml is in use by task gecjl4tuafn581fdfxl0eqxlk
```
You can inspect the task with:
```
sudo docker inspect --type task gecjl4tuafn581fdfxl0eqxlk
```
If the task is bogus the last resort is for the node to forcefully leave the swarm with `docker swarm leave -f`.

To test the network and if the IPAM driver can allocate IP addresses from the subnet must attach a container to it:
```
sudo docker run -it -d --name sleep1 --network sleep-big-net alpine sleep 10d
```
Note that for any error must first check the `docker.service` log with `journalctl -u docker.service`.

##### Overlay networks and VXLAN
The overlay network driver uses the VXLAN protocol extend the Ethernet networks over multiple nodes.
This type of network assumes that each machine has a VTEP or VXLAN Tunnel Endpoint. 
On Docker each custom overlay network will have a unique `sanbox`, network stack or network namespace.
Inside the sanbox there is a brigde `br0` device that has attached the following interfaces:
* `vxlan0`: the VXLAN device that enables the tunnel communication with the "remote" host; in our case via another tunnel interface `tun0`.
* `vethx` : one of the virtual Ethernet interface pair; the other end is assigned in the sanbox where the actual container runs.
The `br0` is the only interface that has assigned an IP address and it act as the gateway for this network.
A clear picture of the architecture is described [here](https://nigelpoulton.com/demystifying-docker-overlay-networking/).

##### How to start debugging overlay network issues
To enter the overlay network sanbox first we must get the actual network namespace. Note that the sanbox is created only after the
first container is created on the current node and attached to this network.

Next we need the hash for the overlay network:
```
$ sudo docker network ls -qf 'name=sleep-big-net'
j51lucnz16xv 
```
Using the first `10` digits of this hash we search the directory where Docker bind mounts the network namespaces:
```
sudo find /run/docker/netns/ -iname *j51lucnz16*
/run/docker/netns/1-j51lucnz16
```
To view the network stack or run a command from this namespace we use `nsenter` command:
```
sudo nsenter --net=/run/docker/netns/1-j51lucnz16 <command>
```
For e.g. to show the vxlan interface details run:
```
$ sudo nsenter --net=/run/docker/netns/1-j51lucnz16 ip -d link show type vxlan
482: vxlan0@if482: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master br0 state UNKNOWN mode DEFAULT group default
    link/ether ee:2e:b0:b4:f1:e4 brd ff:ff:ff:ff:ff:ff link-netnsid 0 promiscuity 1 minmtu 68 maxmtu 65535
    vxlan id 4097 srcport 0 0 dstport 4789 proxy l2miss l3miss ttl auto ageing 300 udpcsum noudp6zerocsumtx noudp6zerocsumrx
    bridge_slave state forwarding priority 32 cost 100 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8001 port_no 0x1 designated_port 32769 designated_cost 0 designated_bridge 8000.3a:1c:8a:57:a4:92 designated_root 8000.3a:1c:8a:57:a4:92 hold_timer    0.00 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on mcast_to_unicast off neigh_suppress off group_fwd_mask 0 group_fwd_mask_str 0x0 vlan_tunnel off isolated off addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
```

To view if the `UDP` communication ports are opened use the socket investigation tool `ss`:
```
$ sudo ss -lupe | grep docker
UNCONN 0      0            0.0.0.0:4789       0.0.0.0:*    ino:12283438 sk:273 cgroup:/system.slice/docker.service <->
UNCONN 0      0                  *:7946             *:*    users:(("dockerd",pid=1852346,fd=29)) ino:12284195 sk:274 cgroup:/system.slice/docker.service v6only:0 <->
```
Note that for VXLAN connections the kernel driver is responsible for opening and listening on default UDP port `4789`.
This is the reason the `ss` command won't show a process id as with the `7946` port.

Since the `vxlan0` is a switch port on the bridge `br0` we can use the `bridge` utility
to show the _learned_ mac addresses of the Ethernet interfaces on the other end of the tunnel.
The mac addresses are stored in the forwarding data base of _fdb_:
```
$ sudo nsenter --net=/run/docker/netns/1-j51lucnz16 bridge fdb show dev vxlan0
c2:b4:01:ad:06:10 master br0 permanent
```

Lastly, to investigate VXLAN packets exchanged over the tunnel interface use the cli tool called `tshark` as follows:
```
sudo tshark -V -i tun0 port 4789
```
##### Fixing the firewall configuration to permit the control and data plane communication
It is common for cloud provided Linux VMs or some distributions to provide some basic firewall configuration and restrict some ports.
Even though we are using a tunnel to securely link to hosts the firewall configuration can prevent communication on some ports.
As we mentioned in the introduction the swarm mode requires that the two machines must open the ports `2377` (tcp), `7946` (udp, tcp) and `4789` (udp, VXLAN). 
Oddly, the Docker network library doesn't do this implicitly. This leaves us to manually fix the firewall rules and permit traffic on these ports.

The firewall rules are usually managed and enforced by a kernel module called _network filter_ or _netfilter_.
These rules can be inserted by using the old tool _iptables_ or the new one _nftables_.
Since the newer distributions will provide the newer we will focus on fixing the rules using the _nftables_ tool.

Since modifying `nftables` rules requires some knowledge on how and when the rules apply to some type of traffic please check the [nftables quick reference](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes)
or check this [how to modify nftables ruleset and firewall rules tutorial](./modify_nftables_ruleset_and firewall_rules.md).

The generic method to figure out if a port is opened or not implies using a tcp/udp client sever like `nc` (netcat) 
and modify the nftables rules set.

To start the server on some port run `nc -l 2378`. Note that some `nc` versions use the `-p` to specify the port.
To listen on UDP port add `-u` option. To open the client run `nc <host ip> <port>`.
Additionally, we can use the `tshark` tool to check the TCP connect flags exchanged between the two hosts.
The following basic tips can be useful when investigating TCP connect issues:
* if the server sends no reply `ACK` packet or an ICMP message this is likely sent by the firewall when access is denied
* when the server sends `ACK` and `RST` flags it means that no port is opened

Since each Linux distribution can provide a custom set of firewall rules it's difficult to provide a fix all solution.
Instead we can follow these simple tips to figured out and fix the nftables configuration.
0. All query and update commands require `root` privilege access.
1. List the full configuration: `nft list ruleset`.
2. Identify which chains have the default policy as `drop`.
Inside the chain definition there should be a line similar to
`type filter hook forward priority filter; policy drop;`.
Note that the `hook` can be different but usually this is
`policy` is related to _forward_ (the packet is forwarded to the next interface) or
_input_ (the packet is about to be sent to the listening socket) hooks.
To fix it must insert an `accept` rule at any position but before any `drop` rules.
3. Identify the rules in each chain that end with the `drop` verdict.
To fix this rules must insert an `accept` rule before the first `drop` rule.
4. Rules are applied to each packet depending on `where` (aka hook) the packet is processed by the network stack
5. There can be multiple chains (group of rules) for the same `hook`
6. Rules within each chain are checked in the order of declaration and that is why is important the order
7. Chains are similar to functions since you can return or jump to the next chain
8. Rules are like instructions in a function and they are executed in the order of declaration

For a quick overview of the `nfttables` format check the 
[quick nftables reference](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes)

For example if a chain for the _input_ hook looks like:
```
$ sudo nft -a list chain ip filter INPUT
table ip filter {
        chain INPUT { # handle 1
                type filter hook input priority filter; policy accept;
                ct state related,established counter packets 5840802 bytes 1724916559 accept # handle 5
                meta l4proto icmp counter packets 12 bytes 1500 accept # handle 6
                iifname "lo" counter packets 120277 bytes 12149282 accept # handle 7
                meta l4proto udp udp sport 123 counter packets 0 bytes 0 accept # handle 8
                meta l4proto tcp ct state new tcp dport 22 counter packets 171141 bytes 19631141 accept # handle 9
                counter packets 30749 bytes 4602605 reject with icmp type host-prohibited # handle 10
        }
}
```
Note:
* use `-a` to show the positions or rule handle ids; for e.g. `handle 9`
* `ip` represents the `ipv4` table family type; other types are arp, ip6, bridge, inet and netdev
* `filter` : the chain type available in table types arp, bridge, ip, ip6 and inet; other chain types are:
	* route: supported by ip and ip6
	* nat: to perform Network Address Translation and supported by ip and ip6
* 'INPUT' : the chain name
* the `type filter hook input priority filter; policy accept;` does the following:
	* declares the `filter` chain type
	* sets this rules chain for the `input` hook; the usual firewall configuration contains
	hooks from IP L3 layer (table families ip, ip6, inet): prerouting,	input, forward, output, postrouting
	For a complete view check the [netfilter hooks](https://wiki.nftables.org/wiki-nftables/index.php/Netfilter_hooks)
	* sets the chain priority as there can be multiple chain with the sanme type; default priority is `0` or `filter`
	* between commas is the default policy: drop or accept
* if we analyze the rules we see that the accept rules for port `22` (ssh) or for `lo` loopback interface are above the
`reject with icmp type host-prohibited` rule

First let's allow communication on tcp port `2378` and verify it with `nc` server-client communication on that port.
We add two rules: one before and one after the `reject` rule. Both rules contain the
[counter](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Counter)
statement to debug how many packets match our rule. In the next `nftables` commands we use the `handle` option
to place a rule `above` the `reject` rule with `handle 10`:
```
sudo nft insert rule ip filter INPUT position 10 tcp dport 2378 counter accept
sudo nft add rule ip filter INPUT tcp dport 2378 counter accept
```
After we test that the `nc` server client communication we check the `INPUT` chain again:
```
tcp dport 2378 counter packets 4 bytes 240 accept # handle 205
counter packets 30749 bytes 4602605 reject with icmp type host-prohibited # handle 10
tcp dport 2378 counter packets 0 bytes 0 accept # handle 203
```
Note:
* the first `accept` rules starts to match and accept packets
* the `reject` and our last rule don't match any packets

To fix the communication for our Docker overlay network we must allow the ports
`2377` (tcp), `7946` (udp, tcp) and `4789` (udp, VXLAN). Instead of adding several
entries we can use the [meta](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Meta)
statement to match mutiple protocols and ports:
```
sudo nft insert rule ip filter INPUT position 10 meta l4proto {tcp, udp} th dport {2377, 4789, 7946} counter accept
```

##### Start overlay communication
With the firewall rules fixed we can add `docker02` to the swarm.
To get the right token to add a `worker` or `manager` we can use the `join-token` subcommand. For e.g. if we want to show the `worker` join token:
```
sudo docker swarm join-token worker
```
Next on `docker02` we attach a new container to the overlay network:
```
sudo docker run -it -d --name sleep2 --network sleep-big-net alpine sleep 10d 
```
To test the connectivity we just need to run the ping command:
```
docker02:~$ sudo docker exec sleep2 ping -c1 sleep1
PING sleep1 (172.30.1.2): 56 data bytes
64 bytes from 172.30.1.2: seq=0 ttl=64 time=69.826 ms

--- sleep1 ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 69.826/69.826/69.826 ms
```
If we ping this container from the container created on `docker01` we get:
```
docker01:~$ sudo docker exec sleep1 ping -c1 sleep2
[sudo] password for catalin:
PING sleep2 (172.30.1.4): 56 data bytes
64 bytes from 172.30.1.4: seq=0 ttl=64 time=67.797 ms

--- sleep2 ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 67.797/67.797/67.797 ms
```
Note:
* the DNS work on both containers as both can find each other by the name provided to the `--name` option
* the allocated IPs for each container pertain to the provided subnet of the overlay network

We can also verify a TCP connection with `nc` using the container or process namespaces.
First wee need to get the process id for each container with:
```
SLEEP_PID=$(sudo docker container inspect sleep1 -f '{{json .State.Pid}}')
```
An then use `nsenter` to run `nc` in the `net` namespace of each process:
* On `docker01` we launch the server:
```
sudo nsenter -t $SLEEP_PID -n nc -l -p 2023
```
* On `docker02` we start the client as:
```
echo "hello" | sudo nsenter -t $SLEEP_PID -a nc sleep1 2023
```
If the TCP connection is OK we should see a "hello" message on server side.

To get more details on how DNS works in Docker please read [How DNS works on Docker](./how_dns_works_on_docker.md).

<a name="ipv6_swarm_overlay_issues"></a>
#### Open github issues IPv6 and Docker swarm
If the `journalctl -u docker.service` contains an error with the message
`Invalid address <IPv6 address>: It does not belong to any of this network's subnets`
chances are that the issue is one of the following:
* [Docker swarm init does not enable ipv6 networking even with ipv6 listening address](https://github.com/moby/moby/issues/24379)
* [Unable to create IPv6-enabled Docker Swarm network](https://github.com/moby/moby/issues/43615)
* [Docker swarm + IPv6 + nftables: IPv6 connectivity](https://github.com/b-data/docker-swarm-ipv6-nftables/blob/main/NOTES.md#ipv6-connectivity)
* [Swarm overlay network doesn't work when advertised over IPv6](https://github.com/moby/moby/issues/43643)
* [Intra-container name resolution seems broken in a overlay network with IPv6](https://github.com/moby/moby/issues/42712)

#### References
* [OpenSSH remote login client](https://www.man7.org/linux/man-pages/man1/ssh.1.html)
* [OpenSSH client configuration file](https://www.man7.org/linux/man-pages/man5/ssh_config.5.html)
* [SSH Tunneling Explained](https://goteleport.com/blog/ssh-tunneling-explained/)
* [Docker overlay networks](https://docs.docker.com/network/overlay/)
* [VPN over SSH](https://wiki.archlinux.org/title/VPN_over_SSH)
* [Overlay networking tutorial](https://docs.docker.com/network/network-tutorial-overlay/)
* [VXLAN & Linux](https://vincent.bernat.ch/en/blog/2017-vxlan-linux)
* [IPv6 not working on Docker swwarm mode](https://superuser.com/questions/1373185/ipv6-does-not-work-in-docker-swarm)
* [Docker IPv6](https://gdevillele.github.io/engine/userguide/networking/default_network/ipv6/)
* [Docker swarm networking](https://gdevillele.github.io/engine/swarm/networking/)
* [Introduction to Linux interfaces for virtual networking](https://developers.redhat.com/blog/2018/10/22/introduction-to-linux-interfaces-for-virtual-networking)
* [How to create docker ingress network with ipv6 support](https://serverfault.com/questions/933211/how-to-create-docker-ingress-network-with-ipv6-support)
* [Demystifying Docker overlay networking](https://nigelpoulton.com/demystifying-docker-overlay-networking/)