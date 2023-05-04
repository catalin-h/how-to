### How DNS works on Docker

#### Overview
* For the next examples we will use Docker version 23.0.3, build 3e7cbfd
* Linux kernel is 5.10.0-21-amd64
* The DNS works only if a network was assigned to the container
* Within the container the actual DNS servers or nameservers depends on
how it was started (w/ or w/o `--dns` option) and the assigned network
(default or custom network)
* Docker uses the Container Network Model or CNM [design](https://github.com/docker/libnetwork/blob/master/docs/design.md)
which defines the following components:
	* Sandbox: represents a way to isolated networks: a network namespace with different net devices, interfaces, IPv4 and IPv6 protocol stacks, TCP ports, sockets, routing tables and firewall rules and a DNS server configuration.
	* Network: a software implementation of the network switch or bridge (IEEE 802.1d) that groups together one or more Sandboxes.
	* Endpoint: a virtual network interface that connects Sandboxes with Networks. Currently on Linux a pair of [veth](https://man7.org/linux/man-pages/man4/veth.4.html) (Virtual Ethernet Device) are used to connect a Sandbox to a Network.
* Besides cgroups Docker uses [namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) to isolate the process `views` of the system. Linux provides the following namespaces:
	* |Namespace | Isolates
:--- | ---:|
|cgroup | Cgroup root rectory
|ipc|  System V IPC, POSIX message queues
|net|  Network devices, stacks, ports, etc.
|mnt| Mount points
|pid| Process IDs and `/proc` mount
|time| Boot and monotonic clocks
|user| User and group IDs
|uts| Hostname and NIS domain name

#### Linux namespaces implementation overview
Linux `namespaces` are exposed by `nsfs`, a pseudo-filesystem that can't be explicitly mounted as `cgroup fs` and it can't be listed by `/proc/filesystems`.
>Each process has a /proc/PID/ns directory that contains one file for each type of namespace. Starting in Linux 3.8, each of these 
files is a special symbolic link that provides a kind of handle for performing certain operations on the associated namespace for the process.
([namespaces in operation](#namespaces_in_operation))

One way to show the namespaces for a process is to use the `lsns` tool:
```
sudo lsns -p $$
```
```
        NS TYPE   NPROCS PID USER COMMAND
4026531834 time      167   1 root /lib/systemd/systemd --system --deserialize 37
4026531835 cgroup    166   1 root /lib/systemd/systemd --system --deserialize 37
4026531836 pid       166   1 root /lib/systemd/systemd --system --deserialize 37
4026531837 user      166   1 root /lib/systemd/systemd --system --deserialize 37
4026531838 uts       163   1 root /lib/systemd/systemd --system --deserialize 37
4026531839 ipc       166   1 root /lib/systemd/systemd --system --deserialize 37
4026531840 mnt       157   1 root /lib/systemd/systemd --system --deserialize 37
4026531992 net       165   1 root /lib/systemd/systemd --system --deserialize 37
```
Note that running the same command without `sudo` will show a different `NRPROCS` as they run for current user, but they share the same `NS` id (first column).
This means that processes from different users can share the same namespace. This will be useful when explaining the Docker `embedded` DNS server feature.
Also, `lsns` will show a namespace only if there are processes running in namespace.

Another way is to list the files from `procfs`:
```
ls -l /proc/$$/ns | awk '{print $1, $9, $10, $11}'
```
```
total
lrwxrwxrwx cgroup -> cgroup:[4026531835]
lrwxrwxrwx ipc -> ipc:[4026531839]
lrwxrwxrwx mnt -> mnt:[4026531840]
lrwxrwxrwx net -> net:[4026531992]
lrwxrwxrwx pid -> pid:[4026531836]
lrwxrwxrwx pid_for_children -> pid:[4026531836]
lrwxrwxrwx time -> time:[4026531834]
lrwxrwxrwx time_for_children -> time:[4026531834]
lrwxrwxrwx user -> user:[4026531837]
lrwxrwxrwx uts -> uts:[4026531838]
```
Note:
* $$ is the bash variable for the current process id
* each file is actually a link, hence the `l` from file flags and `-l` passed to `ls`
* the links point to an empty file in the `nsfs` with a name format: `namespace_name`[`inode index`]

>One use of these symbolic links is to discover whether two processes are in the same namespace.
The kernel does some magic to ensure that if two processes are in the same namespace,
then the inode numbers reported for the corresponding symbolic links in /proc/PID/ns
will be the same. The inode numbers can be obtained using the stat() system call
(in the st_ino field of the returned structure)([namespaces in operation](#namespaces_in_operation))

The inode info on the link:
```
stat /proc/$$/ns/time
```
```
  File: /proc/561786/ns/time -> time:[4026531834]
  Size: 0               Blocks: 0          IO Block: 1024   symbolic link
Device: 14h/20d Inode: 5837954     Links: 1
Access: (0777/lrwxrwxrwx)  Uid: ( 1000/ catalin)   Gid: ( 1000/ catalin)
Access: 2023-05-03 07:44:30.709287629 -0400
Modify: 2023-05-03 07:38:26.047117988 -0400
Change: 2023-05-03 07:38:26.047117988 -0400
```

The inode info on the actual `nsfs` file (add `-L` option):
```
stat -L /proc/$$/ns/time
```
```
  File: /proc/561786/ns/time
  Size: 0               Blocks: 0          IO Block: 4096   regular empty file
Device: 4h/4d   Inode: 4026531834  Links: 1
Access: (0444/-r--r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2023-05-03 08:10:08.568334154 -0400
Modify: 2023-05-03 08:10:08.568334154 -0400
Change: 2023-05-03 08:10:08.568334154 -0400
 Birth: -
```
If this inode was the metadata for a regular file then the `Device: 4h/4d` would indicate the actual block or char device
where the file is stored and would be available in `/dev`.
If we try to find the actual device and where it is mounted we get just `nsfs`:
```
sudo df -ai /proc/$$/ns/time
```
```
Filesystem     Inodes IUsed IFree IUse% Mounted on
nsfs                0     0     0     - /run/docker/netns/d414332231a4
```
If we try to find all mounts for the `nsfs` we get:
```
findmnt --all -t nsfs
```
```
TARGET                         SOURCE                 FSTYPE OPTIONS
/run/docker/netns/d414332231a4 nsfs[net:[4026532276]] nsfs   rw
```

Note:
* the mount point `/run/docker/netns/d414332231a4` is a [bind mount](#bind_mount) was created by Docker (probably)
to avoid destroying the namespace when there are no processes left assigned to the namespace
* on machines without Docker installed the above commands would probably return nothing if there no bind mounts to existing namespaces.
* the `NetworkSettings.SandboxKey` key returned by `docker inspect` command represents the mount point of the
network namespace where the container runs.

>The /proc/PID/ns symbolic links also serve other purposes. If we open one of these files,
then the namespace will continue to exist as long as the file descriptor remains open,
even if all processes in the namespace terminate. The same effect can also be obtained
by bind mounting one of the symbolic links to another location in the file system. ([namespaces in operation](#namespaces_in_operation))

In other words to create a new bind mount point for a namespace file:
* create a mount point file
```
touch my_time
```
* use `bind --mount`
```
sudo mount --bind /proc/$$/ns/time my_time
```
If we run the `stat -L my_time` command we get:
```
  File: my_time
  Size: 0               Blocks: 0          IO Block: 4096   regular empty file
Device: 4h/4d   Inode: 4026531834  Links: 1
Access: (0444/-r--r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2023-05-03 10:01:25.226543362 -0400
Modify: 2023-05-03 10:01:25.226543362 -0400
Change: 2023-05-03 10:01:25.226543362 -0400
 Birth: -
```
and the `findmnt -k --all -t nsfs` will show our bind mount point also:
```
TARGET                         SOURCE                  FSTYPE OPTIONS
/run/docker/netns/d414332231a4 nsfs[net:[4026532276]]  nsfs   rw
/home/catalin/my_time          nsfs[time:[4026531834]] nsfs   rw
```
To remove the mount just run the `umount` as root:
```
sudo umount my_time
```

The only way to create namespace is not by using the nsfs but by using the syscalls [clone](https://man7.org/linux/man-pages/man2/clone.2.html) and [unshare](https://man7.org/linux/man-pages/man2/unshare.2.html) and require the `CAP_SYS_ADMIN` capability.
This means that for a new namespace to live after the last process exists and run processes in this namespace after that,
one of the processes running initially on that namespace must bind-mount its /proc/$$/ns/<ns> to an existing mount point visible from parent process:
* create the mount point visible in the parent process
```
touch my_net_ns
```
* start a process in a new namespace and bind mount that namespace file `/proc/$$/ns/<ns>` to the mount point

Luckily, the [unshare](https://man7.org/linux/man-pages/man1/unshare.1.html) command does the last step and creates the bind for the file provided as parameter (e.g. `--net=<mount point>`):
```
sudo unshare --net=my_net_ns bash -c "ip a && ls -il /proc/self/ns/net"
```
```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
6057145 lrwxrwxrwx 1 root root 0 May  3 11:20 /proc/self/ns/net -> 'net:[4026532269]'
```
The above command starts a `bash` process in a new network namespace and bind mounts this namespace to existing file `my_net_ns`.
The bash command executes the following commands:
* `ip a` in order to list the available network interfaces
* lists the `/proc/self/ns/net` file in order to see created inode for the network namespace
If we find all `nsfs` the mounts with `findmnt --all -t nsfs` we get:
```
TARGET                  SOURCE                 FSTYPE OPTIONS
/home/catalin/my_net_ns nsfs[net:[4026532269]] nsfs   rw
```
Note that is the _same_ network namespace created by `unshare` command.

If we try to run the same `unshare` command again the kernel will create a new network namespace but linked to that first one:
```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
6061632 lrwxrwxrwx 1 root root 0 May  3 11:25 /proc/self/ns/net -> 'net:[4026532387]
```
The `findmnt --all -t nsfs` will show the relation between namespaces
```
TARGET                    SOURCE                 FSTYPE OPTIONS
/home/catalin/my_net_ns   nsfs[net:[4026532269]] nsfs   rw
L¦/home/catalin/my_net_ns nsfs[net:[4026532387]] nsfs   rw
```
and `ls -il my_net_ns` will show the last created namespace:
```
4026532387 -r--r--r-- 1 root root 0 May  3 11:25 my_net_ns
```
In order to see if these two network namespaces are distinct lets modify the `lo` interface in
the child namespace and see if modification is replicated in the parent namespace. To do that we use
`nsenter` to execute processes inside namespaces:
Modify `lo` in parent namespace:
```
sudo nsenter --net=my_net_ns ip address add 127.0.0.1/255.0.0.0 dev lo
```
To check run:
```
sudo nsenter --net=my_net_ns ip address show
```
And we get
```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
```
Then unbind the child namespace with `sudo umount my_net_ns` and check the net namespaces again:
```
TARGET                  SOURCE                 FSTYPE OPTIONS
/home/catalin/my_net_ns nsfs[net:[4026532269]] nsfs   rw
```
If we check the net interfaces from current net namespace we see that the change didn't propagate:
```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000                                                                                                                        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 
```
The same is true if we modified something in the parent namespace and then create the child which will not contain the change.

Note that after running the second `unshare` command the _parent_ namespace becomes unreachable and
the only way to run processes in it is to remove all the ancestors. To overcome that, before running the second `unshare` must create
another bind mount but with `--make-private` option:
```
sudo mount --make-private --bind my_net_ns my_net_ns_parent
```
After running the `findmnt` command we see that `my_net_ns_parent` mount point points to the parent namespace:
```
TARGET                         SOURCE                 FSTYPE OPTIONS
 /home/catalin/my_net_ns        nsfs[net:[4026532269]] nsfs   rw	
 L¦/home/catalin/my_net_ns      nsfs[net:[4026532387]] nsfs   rw
 /home/catalin/my_net_ns_parent nsfs[net:[4026532269]] nsfs   rw
```

#### Docker and Linux namespaces
Each Docker container runs in its own set of namespaces and from network perspective in its own sandbox.
In the last section we saw that a process can execute in any of the existing namespaces that we created.
Lets test if we can run any process in the namespaces that Docker creates.

First, lets create a long running container named _sleepy_default_dns_ that based on `Alpine` Linux distribution and will run the `sleep 10d` command without any capabilities (`--cap-drop=all`).
```
sudo docker run -d --name sleepy_default_dns --cap-drop=all alpine:latest sleep 10d
```
We can check immediately that there is a mount for the namespaces that Docker creates with `findmnt --all -t nsfs`:
```
TARGET                         SOURCE                 FSTYPE OPTIONS
/run/docker/netns/4ff08ad514a4 nsfs[net:[4026532275]] nsfs   rw
```
In order to see the full set we need the process id.
We know that containers are actually processes and in our case it's the process that run the `sleep 10d` command.
To get the process id we use `docker inspect`:
```
CONTAINER_PID=$(sudo docker inspect sleepy_default_dns -f '{{json .State.Pid}}')
```
Note that we save the process id a variable to help us retain a name instead of a number.

If we run ```sudo lsns -p $CONTAINER_PID``` we can see that there are different namespaces
than current bash process and the `net` namespace corresponds to the namespace that `findmnt` found above:
```
        NS TYPE   NPROCS    PID USER COMMAND
4026531834 time      168      1 root /lib/systemd/systemd --system --deserialize 37
4026531837 user      167      1 root /lib/systemd/systemd --system --deserialize 37
4026532270 mnt         1 890873 root sleep 10d
4026532271 uts         1 890873 root sleep 10d
4026532272 ipc         1 890873 root sleep 10d
4026532273 pid         1 890873 root sleep 10d
4026532275 net         1 890873 root sleep 10d
4026532451 cgroup      1 890873 root sleep 10d
```

Next, let's first try to run a process using the Docker way with `docker exec`:
```
sudo docker exec -it sleepy_default_dns ip a 
```
The above command will show the interfaces from the container `net` namespace:
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
35: eth0@if36: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```
Let's try use the `nsenter` with the container process id as target pid and _only_ considering the `net` namespace to run the same command:
```
sudo nsenter -t $CONTAINER_PID -n ip a
```
The output should be the same:
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
35: eth0@if36: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```
In the last section we noted that Docker creates pairs of `Virtual Ethernet Device` or [veth](#veth).
To illustrate this let's list all interface of this type in current:
```
ip a show type veth 
```
```
36: veth8b82c07@if35: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master docker0 state UP group default
    link/ether 82:a8:33:0b:e0:39 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet6 fe80::80a8:33ff:fe0b:e039/64 scope link
       valid_lft forever preferred_lft forever
```
and container net namespace:
```
sudo nsenter -t $CONTAINER_PID -n ip a show type veth
```
```
35: eth0@if36: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```
Note that the one of the properties of the `veth` interface from current namespace is `master docker0`.
The `docker0` interface represents the _bridge_ or the software implementation of a Ethernet _switch_
that Docker creates by default:
```
ip a show type bridge
```
```
3: docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:90:3f:ed brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever
    inet6 fe80::42:acff:fe90:3fed/64 scope link
       valid_lft forever preferred_lft forever
```
This interface is used to link or group containers that use the default Docker network called `brigde`
and uses the [bridge](https://docs.docker.com/network/bridge/) driver:
```
$ sudo docker network ls
NETWORK ID     NAME      DRIVER    SCOPE
aaa0ddc2ab07   bridge    bridge    local
a95a6729bcef   host      host      local
048bf02c58b6   none      null      local
```
```
$ sudo docker network inspect bridge
[
    {
        "Name": "bridge",
        "Id": "aaa0ddc2ab0744f882b2ce67f235e3fd927093078f6738cf999ccf8419bc4329",
        "Created": "2023-04-09T07:29:30.871139969-04:00",
        "Scope": "local",
        "Driver": "bridge",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": null,
            "Config": [
                {
                    "Subnet": "172.17.0.0/16"
                }
            ]
        },
        "Internal": false,
        "Attachable": false,
        "Ingress": false,
        "ConfigFrom": {
            "Network": ""
        },
        "ConfigOnly": false,
        "Containers": {
            "d01ddd574a7fec2e406d47fb9f49aac1b891e0b781d94e87d7948072368f7ffc": {
                "Name": "sleepy_default_dns",
                "EndpointID": "8fc29b549031c4f32cd574b3dbbecef6750fb5d569b8db457c519dcfaed10242",
                "MacAddress": "02:42:ac:11:00:02",
                "IPv4Address": "172.17.0.2/16",
                "IPv6Address": ""
            }
        },
        "Options": {
            "com.docker.network.bridge.default_bridge": "true",
            "com.docker.network.bridge.enable_icc": "true",
            "com.docker.network.bridge.enable_ip_masquerade": "true",
            "com.docker.network.bridge.host_binding_ipv4": "0.0.0.0",
            "com.docker.network.bridge.name": "docker0",
            "com.docker.network.driver.mtu": "1500"
        },
        "Labels": {}
    }
]
```
The last thing to note is that all the above commands are using _only_ the net namespace.
If we suppose to use a tool that exists only in Alpine we would get an error:
```
$ sudo nsenter -t $CONTAINER_PID -n ifconfig
nsenter: failed to execute ifconfig: No such file or directory
```
To fix that lets consider the `mnt` namespace when running the `nsenter` command:
```
$ sudo nsenter -t $CONTAINER_PID -n -m ifconfig
ifconfig: /proc/net/dev: No such file or directory
eth0      Link encap:Ethernet  HWaddr 02:42:AC:11:00:02
          inet addr:172.17.0.2  Bcast:172.17.255.255  Mask:255.255.0.0
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1

lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
```
This is better but still we get an error about not proc fs.
To fix this issue must consider the `pid` namespace by adding the `-p` flag.
However, in order to enter all namespaces from the target pid the `nsenter` command provide the `-a` flag which we will use from now on:
```
sudo nsenter -t $CONTAINER_PID -a ifconfig
```
Now the command executes successfully:
```
eth0      Link encap:Ethernet  HWaddr 02:42:AC:11:00:02
          inet addr:172.17.0.2  Bcast:172.17.255.255  Mask:255.255.0.0
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:39 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0
          RX bytes:4584 (4.4 KiB)  TX bytes:0 (0.0 B)

lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)
```
#### Default DNS server on Docker
On Linux systems the DNS resolver from `libc` uses the [resolver configuration file](https://www.man7.org/linux/man-pages/man5/resolv.conf.5.html) 
found at `/etc/resolv.conf`. There are [other](#dns_setup) ways to configure the DNS but Docker seems to prefer to modify this file.

When using the default network called `bridge` Docker uses the nameservers from the host system `/etc/resolv.conf`.
We can check this by reading this file from container context with ```sudo docker exec -it sleepy_default_dns cat /etc/resolv.conf```:
```
# Generated by NetworkManager
search homer
nameserver 192.168.1.1
```
When we launch a new container Docker cli provides the `--dns` option to pass one or more dns servers.
Lets run another long running container using the default network but with two dns servers:
```
sudo docker run -d --name sleepy_with_dns_srv --cap-drop=all --dns 1.1.1.1 --dns 8.8.8.8 alpine:latest sleep 10d
```
When we read the `resolv.conf` from that container context we see that Docker uses only the dns sever provided at launch and ignored the host configuration:
```
sudo docker exec -it sleepy_with_dns_srv cat /etc/resolv.conf
```
```
search homer
nameserver 1.1.1.1
nameserver 8.8.8.8
```
#### DNS on custom Docker networks
Each custom network on Docker will have it's own default embedded Docker DNS server.
To test that let's create a new `bridge` type network called `my_net`:
```
sudo docker network create my_net
```
List all available networks:
```
sudo docker network ls
```
```
NETWORK ID     NAME      DRIVER    SCOPE
aaa0ddc2ab07   bridge    bridge    local
a95a6729bcef   host      host      local
8e7c1727a906   my_net    bridge    local
048bf02c58b6   none      null      local
```
If we list all _bridge_ interface types we see the new bridge:
```
$ ip a show type bridge
3: docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:90:3f:ed brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever
    inet6 fe80::42:acff:fe90:3fed/64 scope link
       valid_lft forever preferred_lft forever
41: br-8e7c1727a906: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:9f:10:c7:9a brd ff:ff:ff:ff:ff:ff
    inet 172.18.0.1/16 brd 172.18.255.255 scope global br-8e7c1727a906
       valid_lft forever preferred_lft forever
    inet6 fe80::42:9fff:fe10:c79a/64 scope link
       valid_lft forever preferred_lft forever
```
Next, lets create a new container running the same `sleep` command but set the `--net` option:
```
sudo docker run -d --name sleepy_on_my_net --net=my_net --cap-drop=all alpine:latest sleep 10d 
```
As usual Docker creates a new mount point for the net `namespace`:
```
TARGET                         SOURCE                 FSTYPE OPTIONS                                                                                                                         /run/docker/netns/42d76f7cebf2 nsfs[net:[4026532275]] nsfs   rw                                                                                                                              /run/docker/netns/7328faf83948 nsfs[net:[4026532461]] nsfs   rw 
```
If we run `docker inspect` on `my_net` we get:
```
$ sudo docker network inspect my_net
[
    {
        "Name": "my_net",
        "Id": "8e7c1727a906e73730381c1dec82e4ad38d583890736c80c6d877ad3810e95f0",
        "Created": "2023-05-04T06:57:49.783492692-04:00",
        "Scope": "local",
        "Driver": "bridge",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "172.18.0.0/16",
                    "Gateway": "172.18.0.1"
                }
            ]
        },
        "Internal": false,
        "Attachable": false,
        "Ingress": false,
        "ConfigFrom": {
            "Network": ""
        },
        "ConfigOnly": false,
        "Containers": {
            "fa5cb4772b728c52d7b444286a460cd201ca061b376c59d342ffd9b062f94dc9": {
                "Name": "sleepy_on_my_net",
                "EndpointID": "82818e1d33f946c8b3e425c84c5cf2ed887fd23148dd8d67ddb648d419b6f0aa",
                "MacAddress": "02:42:ac:12:00:02",
                "IPv4Address": "172.18.0.2/16",
                "IPv6Address": ""
            }
        },
        "Options": {},
        "Labels": {}
    }
]
```
Note:
* the `Id`,  field and the bridge interface name share the same hash
* the `Containers` field contains the list of container sharing the same network

This time if we check the `resolv.conf` file with ```sudo docker exec -it sleepy_on_my_net cat /etc/resolv.conf``` we get:
```
search homer
nameserver 127.0.0.11
options ndots:0
```
Note that this time we get a local host address meaning that the nameserver is listening on current machine.

We can test if this address is indeed a DNS server by trying to lookup some domain:
```
$ sudo docker exec -it sleepy_on_my_net nslookup www.google.com
[sudo] password for catalin:
Server:         127.0.0.11
Address:        127.0.0.11:53

Non-authoritative answer:
Name:   www.google.com
Address: 142.250.180.196

Non-authoritative answer:
Name:   www.google.com
Address: 2a00:1450:400d:80e::2004
```

Usually the DNS servers respond on `UDP` port `53` but on container there is no process listening on that address because
the only process that runs is the `sleep` command.
If we remember, Linux namespaces allow running multiple processes in the same namespace.
To investigate what other processes are running in the same namespace as our container lets get its the process id:
```
CONTAINER_PID=$(sudo docker inspect sleepy_on_my_net -f '{{json .State.Pid}}')
```
Then run the `ss` utility to investigate sockets from the net namespace of our container:
```
sudo nsenter -t $CONTAINER_PID -p -n ss --udp -a -p
```
```
State  Recv-Q Send-Q Local Address:Port   Peer Address:Port Process
UNCONN 0      0         127.0.0.11:56877       0.0.0.0:*    users:(("dockerd",pid=4859,fd=35))
```
Note:
* we launch the `nsenter` command with options `-p -n` in order to run it in the `pid` and `net` namespaces because
we had to use the `ss` utility that is not available on the compact Alpine Linux
* running `ss` with the above options will show all (`-a`) UDP (`--udp`) opened sockets and which process owns them (`-p`).

Ok, so a process `dockerd` opened a UDP socket on the same local address `127.0.0.11` in same net namespace but on port `56877`.
The final piece of this puzzle is given by the Docker's _duct tape_ `iptables` and `nftables` - [see](https://www.netfilter.org/).
Since `nftables` is the successor of `iptables` and most likely all modern Linux distribution already provides it, lets show the
rules set from the container net namespace:
```
sudo nsenter -t $CONTAINER_PID -p -n nft list ruleset
```
```
table ip nat {
        chain DOCKER_OUTPUT {
                meta l4proto tcp ip daddr 127.0.0.11 tcp dport 53 counter packets 0 bytes 0 dnat to 127.0.0.11:45783
                meta l4proto udp ip daddr 127.0.0.11 udp dport 53 counter packets 0 bytes 0 dnat to 127.0.0.11:56877
        }

        chain OUTPUT {
                type nat hook output priority -100; policy accept;
                ip daddr 127.0.0.11 counter packets 0 bytes 0 jump DOCKER_OUTPUT
        }

        chain DOCKER_POSTROUTING {
                meta l4proto tcp ip saddr 127.0.0.11 tcp sport 45783 counter packets 0 bytes 0 snat to :53
                meta l4proto udp ip saddr 127.0.0.11 udp sport 56877 counter packets 0 bytes 0 snat to :53
        }

        chain POSTROUTING {
                type nat hook postrouting priority srcnat; policy accept;
                ip daddr 127.0.0.11 counter packets 0 bytes 0 jump DOCKER_POSTROUTING
        }
}
```
Ok, so in the end Docker uses `nftables` and port-NAT to forward UDP datagrams send to `127.0.0.11:53` to `127.0.0.11:56877`.
As we saw earlier, at this UDP port `56877` the Docker embedded DNS server will listen for incoming requests.

The DNS server from the network is also responsible for discovering other containers that are started with `--name` option.
This way every container can find other containers by name regardless of their IP address.
To demonstrate that lets create a new container on the same network and try to `ping` the first created container:
```
$ sudo docker run -d --name sleepy_on_my_net_2 --net=my_net --cap-drop=all alpine:latest sleep 10d
d04ffb81c6a3338ef558e492dfca543e87ef7fc2eaf281679e4cc50d9ba515a8
$ sudo docker exec -it sleepy_on_my_net_2 ping sleepy_on_my_net -c 1
PING sleepy_on_my_net (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=42 time=0.638 ms

--- sleepy_on_my_net ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 0.638/0.638/0.638 ms
```
One more aspect needs to be clarified: what happens when you pass both `--net` and `--dns` options ?
The answer is that Docker will still launch the embedded DNS server but will use the DNS addresses
provided by `--dns` option to search for entries in case it can't resolve the query.

#### References
* [Container Network Model or CNM design](https://github.com/docker/libnetwork/blob/master/docs/design.md)
* <a name="veth"></a>[Virtual Ethernet Device](https://man7.org/linux/man-pages/man4/veth.4.html)
* [Linux namespaces]()
* <a name="namespaces_in_operation"></a>[Namespaces in operation, part 2: the namespaces API](https://lwn.net/Articles/531381/)
* <a name="bind_mount"></a>[What is a bind mount](https://unix.stackexchange.com/questions/198590/what-is-a-bind-mount)
* <a name="dns_setup"></a>[DNS Config Under Linux](https://unix.stackexchange.com/questions/494324/how-to-setup-dns-manually-on-linux)