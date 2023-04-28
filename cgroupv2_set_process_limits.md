### How to set process limits with Linux cgroup v2

#### Prerequisites
The Linux `cgroup` provides a mechanism to hierarchically group processes aka _cgroup core_ and distribute system resources among these processes, aka _cgroup contollers_.
The `cgroup v2` differs from `v1` by creating hierarchies of process groups and assigning to each group in the hierarchy a controller; the latter manages the resources assigned to current group by the parent group controller. The v1 implementation does the opposite and assigns groups of processes (and threads) to controllers.

The simplest way to check the cgroup that process run on is to read the `/proc/<PID>/cgroup`.
For example to find out the cgroups for the current shell runs:
```
$ cat /proc/$$/cgroup
```
On recent distributions the result would be a single group, meaning the v2 is supported:
```
0::/user.slice/user-1001.slice/session-3.scope
```
Older distributions will show the v1 hierarchy pf controllers:
```
13:rdma:/
12:pids:/
11:hugetlb:/
10:net_prio:/
9:perf_event:/
8:net_cls:/
7:freezer:/
6:devices:/
5:blkio:/
4:cpuacct:/
3:cpu:/
2:cpuset:/
1:memory:/
0::/
```
Also, some will show both v1 and v2 hierarchies and group.

Usually `cgroups` are mounted in sysfs: `/sys/fs/cgroup` but can be mounted to another mount point with:
```
# mount -t cgroup2 none $MOUNT_POINT
```

Another way to view cgroups is by using `lscgroup` tool from `cgroup-tools` package.
This tool add limited support for cgroup v2 starting with version 2.0.0.
There is a new version 3.0.0 but it didn't reach the main package repos.
On Debian is experimental.
```
$ apt show cgroup-tools
Package: cgroup-tools
Version: 2.0.2-2
```

On modern distributions the best way view cgroups is to use the systemd tools for cgroups: `systemd-cgtop` and `systemd-cgls`:
```
$ systemd-cgtop
```
```
Control Group                                          Tasks   %CPU   Memory  Input/s Output/s
user.slice                                               297   19.8     3.2G        -        -
user.slice/user-1000.slice                               297   19.8     3.0G        -        -
user.slice/user-1000.slice/session-48.scope               10   20.0   553.5M        -        -
/                                                        436   15.7     4.2G        -        -
user.slice/user-1000.slice/session-794.scope               4    0.1     2.7M        -        -
system.slice                                              82    0.0   822.3M        -        -
system.slice/docker.service                               10    0.0    50.8M        -        -
user.slice/user-1000.slice/user@1000.service             269    0.0     2.1G        -        -
dev-hugepages.mount                                        -      -     8.0K        -        -
dev-mqueue.mount                                           -      -   532.0K        -        -
init.scope                                                 1      -     7.5M        -        -
proc-sys-fs-binfmt_misc.mount                              -      -     4.0K        -        -
sys-fs-fuse-connections.mount                              -      -     4.0K        -        -
sys-kernel-config.mount                                    -      -     4.0K        -        -
sys-kernel-tracing.mount                                   -      -   144.0K        -        -
system.slice/ModemManager.service                          3      -     6.0M        -        -
system.slice/NetworkManager.service                        3      -    13.3M        -        -
system.slice/accounts-daemon.service                       3      -     3.2M        -        -
```
```
$ systemd-cgls
```
```
Control group /:
-.slice
├─user.slice
│ └─user-1000.slice
│   ├─user@1000.service
│   │ ├─session.slice
│   │ │ ├─org.gnome.SettingsDaemon.MediaKeys.service
│   │ │ │ └─1226 /usr/libexec/gsd-media-keys
│   │ │ ├─org.gnome.SettingsDaemon.Smartcard.service
│   │ │ │ └─1261 /usr/libexec/gsd-smartcard
│   │ │ ├─org.gnome.SettingsDaemon.Datetime.service
│   │ │ │ └─1216 /usr/libexec/gsd-datetime
│   │ │ ├─org.gnome.SettingsDaemon.Housekeeping.service
│   │ │ │ └─1219 /usr/libexec/gsd-housekeeping
│   │ │ ├─org.gnome.SettingsDaemon.Keyboard.service
│   │ │ │ └─1220 /usr/libexec/gsd-keyboard
│   │ │ ├─org.gnome.SettingsDaemon.A11ySettings.service
│   │ │ │ └─1214 /usr/libexec/gsd-a11y-settings
│   │ │ ├─org.gnome.SettingsDaemon.Wacom.service
│   │ │ │ └─1288 /usr/libexec/gsd-wacom
│   │ │ ├─org.gnome.SettingsDaemon.Sharing.service
│   │ │ │ └─1246 /usr/libexec/gsd-sharing
│   │ │ ├─org.gnome.SettingsDaemon.Color.service
```
The same tree list view of cgroups can be displayed using:
```
systemctl status
```

#### Limiting the memory for userland processes
The `memory` controller tracks the following memory zones:
* Userland memory - page cache and anonymous memory.
* Kernel data structures such as dentries and inodes.
* TCP socket buffers.

The admin users will use the cgroup `memory interface files` to limit process resources bounds.
The file interface typically are read-write files found in cgroup sysfs under each group with the
naming convention _controller_name_._limit_name_.

For example, the memory controller has the following files in each group:
* `memory.current` : a read-only single value representing the total amount of memory
currently being used by the cgroup and its descendants.
* `memory.high` : a read-write single value with default value `max` representing
the memory usage throttle limit. Above this limit will not kill the processes but will
be pressured to reclaim more memory.
* `memory.max` : a read-write single value with default value `max` representing
the memory usage hard limit. Above this limit processes running in the cgroup can
be terminated by OOM killer.
* `memory.events` : a read-only flat-keyed file contains memory events related to this cgroup hierarchy;
one important property is the  `oom_kill` which counts the number of processes belonging to this cgroup
killed by any kind of OOM killer.
* `memory.events.local` : same as `memory.events` but captures events related to current cgroup
and not on the hierarchy.

For the cgroup core some important interface files that worth mentioning are:
* `cgroup.procs` : a read-write file for adding a process to the cgroup (by writing the PID)
and reading the PIDs of all processes which belong to the cgroup (one-per-line).
Note, that a process migrates all threads in the cgroup and can live in a single cgroup.
* `cgroup.controllers` : read only file that lists the available controllers;
* `cgroup.subtree_control` : interface file for enabling controllers from `cgroup.controllers`;
when read, it shows space separated list of the controllers which are enabled to control
resource distribution from the cgroup to its children.
* `cgroup.events` : a read-only flat-keyed file which contains two events:
	* `populated` : it reads 1 if current or child cgroups contain running processes and 0 otherwise
	* `frozen` : it reads 1 if the cgroup is frozen (all processes belonging to this cgroup and descendants are stopped) and 0 otherwise

Note that when dealing with memory the limit values must be multiples of PAGE_SIZE (4k on x86 and possible 8k, 16k on aarch64).
To check the `PAGE_SIZE` that the current kernel was build with run:
```
$ getconf PAGE_SIZE
4096 
```

In next test we will try to modify the `memory.max` limit for a custom cgroup and investigate the aftermath of oom killer action.

Let's mount the cgroup2 in custom mount point `/tmp/cgroup`:
```
mkdir /tmp/cgroup
```
..and mount the cgroup2
```
sudo mount -t cgroup2 none /tmp/cgroup
```
..and check the mounted fs
```
$ ls /tmp/cgroup/
```
```
cgroup.controllers
cgroup.max.depth
cgroup.max.descendants
cgroup.procs
cgroup.stat
cgroup.subtree_control
cgroup.threads
cpu.pressure
cpuset.cpus.effective
cpuset.mems.effective
cpu.stat
dev-hugepages.mount
dev-mqueue.mount
init.scope
io.cost.model
io.cost.qos
io.pressure
io.stat
memory.numa_stat
memory.pressure
memory.stat
-.mount
proc-sys-fs-binfmt_misc.mount
sys-fs-fuse-connections.mount
sys-kernel-config.mount
sys-kernel-debug.mount
sys-kernel-tracing.mount
system.slice
user.slice
```
To create a new custom cgroup just create a directory `my.slice` where the cgroup2 sysfs is mounted, in the `user.slice` group - created by systemd.
```
sudo mkdir /tmp/cgroup/user.slice/my.slice
```
If we list the files on this directory we will notice that the kernel automatically creates the controllers inherited from the parent cgroup:
```
$ ls /tmp/cgroup/user.slice/my.slice
```
```
cgroup.controllers
cgroup.events
cgroup.freeze
cgroup.max.depth
cgroup.max.descendants
cgroup.procs
cgroup.stat
cgroup.subtree_control
cgroup.threads
cgroup.type
io.pressure
memory.current
memory.events
memory.events.local
memory.high
memory.low
memory.max
memory.min
memory.numa_stat
memory.oom.group
memory.pressure
memory.stat
memory.swap.current
memory.swap.events
memory.swap.high
memory.swap.max
pids.current
pids.events
pids.max
```
A cgroup without any processes is considered empty it can be remove a cgroup with `rmdir`:
```
rmdir /tmp/cgroup/user.slice/my.slice
```
If the cgroup is not empty then must first migrate all processes and threads to another
cgroup outside the current hierarchy. Otherwise, the `rmdir` will emit the error:
```
rmdir: failed to remove '/tmp/cgroup/user.slice/my.slice': Device or resource busy
```

To launch the OOM process killer on every memory request we just need to write value `0` in the file interface `/tmp/cgroup/user.slice/my.slice/memory.max`.
Before seeing the memory controller in action (see how the cgrop memory controller oom kill a process when memory reaches the hard limit)
lets see how to run a process within a cgroup. There are two ways to make a process run in a cgroup context:
* the process parent is already in that cgroup and child will inherit this cgroup also
* migrate the process by writing the PID in the `cgroup.procs` file interface of the target cgroup
Note that there is a notable difference between migrating the process and launching from a parent already inside that cgroup.
When migrating a process the controllers enforces the resources limits on next allocation request and not during migration.
This means that processes can be migrated even if the allocated resources are beyond the bounds of the target cgroup.
When the process inherits the parent process cgroup the limits apply immediately.

In order to understand how a process is oom killed by the kernel let's first try to see what files from the cgroup interface change
after we migrate a process and then launch a new process within that cgroup. To achieve that we use two scripts:
* [cgroup_stats.sh](./scripts/cgroup_stats.sh) : displays the custom cgroup info (passed as parameter) and the cgroup name of the process that executes this script
```
#!/bin/sh

printf "[ppid:$PPID, pid:$$] $TITLE\n"
printf " cgroup.events.%s\n" "$(grep 'populated' $1/cgroup.events)"

# Don't read the file with cat since it creates a new process that will be added
# to the cgroup process list
while read -r line; do
  plist="$plist$line "
done < $1/cgroup.procs
printf " cgroup.procs: %s\n" "$plist"

printf " cgroup: %s\n" "$(cat /proc/$$/cgroup)"
```
* [move_to_cgroup.sh](./scripts/move_to_cgroup.sh) : migrates the running process in the custom cgroup (passed as parameter) and then executes the `cgroup_stats.sh` in a child process
```
#!/bin/sh

printf "[ppid:$PPID, pid:$$] Using cgroup: %s\n" "$1"

# Use the dot command (. ./script.sh) to call the script
# on the same process and use TITLE variable to pass the title
TITLE="Before move"
. ./cgroup_stats.sh

# Migrate to cgroup
printf "Migrating $$ to cgroup ...\n"
printf "$$" > $1/cgroup.procs

# Check the cgroup info
TITLE="After move"
. ./cgroup_stats.sh

# Launch a child process to check the assigned cgroup on startup
# Note that the TITLE set is part of the command in order to create
# the envar in the child process evironment.
TITLE="Child" ./cgroup_stats.sh $1
```
If we run the script as root, ```sudo ./move_to_cgroup.sh```, we get something like:
```
[ppid:657049, pid:657050] Using cgroup: /tmp/cgroup/user.slice/my.slice
[ppid:657049, pid:657050] Before move
 cgroup.events.populated 0
 cgroup.procs:
 cgroup: 0::/user.slice/user-1000.slice/session-48.scope
Migrating 657050 to cgroup ...
[ppid:657049, pid:657050] After move
 cgroup.events.populated 1
 cgroup.procs: 657050
 cgroup: 0::/user.slice/my.slice
[ppid:657050, pid:657055] Child
 cgroup.events.populated 1
 cgroup.procs: 657050 657055
 cgroup: 0::/user.slice/my.slice
```
Notes:
* both scripts output the parent and current pid; in the end after launching the child process both pids, `657050 657055`, are in the `cgroup.procs`.
* the parent pid on the first line is the `sudo` process that launched this script as root user
* we need to launch the script as root because we have to migrate/write the pid in `cgroup.procs` file interface
* after migration the cgroup of the process running the script changes from the cgroup `0::/user.slice/user-1000.slice/session-48.scope` where
the shell process runs, to the custom cgroup `0::/user.slice/my.slice`
* after the migration the `cgroup.events.populated` event field changes to `1` and after the script exists and there are no more processes running
in this cgroup it changes back to `0`.
* the child process cgroup is created in the custom cgroup because the parent was running in this cgroup

Now that we see the cgroup file interface changes let's test the OOM kill action on processes in this cgroup by changing the hard limit `memory.max` to `0`:
```
echo 0 | sudo tee /tmp/cgroup/user.slice/my.slice/memory.max
```
Note, that we use unix `tee` command to properly run `sudo` on the actual command that writes
to the sysfs and not the command `echo 0` that builds the string to write. If we were to run
`sudo echo 0 > /tmp/cgroup/user.slice/my.slice/memory.max` we would get `Permission denied` error.

Next we check the `oom_kill` counter from the memory events related to this cgroup memory controller:
```
grep 'oom_kill' /tmp/cgroup/user.slice/my.slice/memory.events
```
I there were no processes terminated because of OOM this command will return `oom_kill 0`.

Now if we run again the script as root, ```sudo ./move_to_cgroup.sh```, we get some interesting results:
```
[ppid:657589, pid:657590] Using cgroup: /tmp/cgroup/user.slice/my.slice
[ppid:657589, pid:657590] Before move
 cgroup.events.populated 0
 cgroup.procs:
 cgroup: 0::/user.slice/user-1000.slice/session-48.scope
Migrating 657590 to cgroup ...
Killed
```
After migrating the process that executes the script the kernel will automatically kill it when it attempts to request some memory and will display the `Killed` message.
To verify that the process was terminated because of the custom cgroup memory controller let's execute again ```grep 'oom_kill' /tmp/cgroup/user.slice/my.slice/memory.events```.
This time this counter will show an incremented value; e.g. if previously the value was `0` now it will be `oom_kill 1`.

#### Limiting the CPU resources

In order to control the CPU resources allocated to a custom cgroup that cgroup must have a `cpu` controller enabled by its parent cgroup.
After checking our custom cgroup for controllers we realize that it's missing:
```
$ cat /tmp/cgroup/user.slice/my.slice/cgroup.controllers
memory pids
```
Luckily the parent cgroup can enabled the `cpu` controller for our custom cgroup:
```
$ cat /tmp/cgroup/user.slice/cgroup.controllers
cpuset cpu io memory hugetlb pids rdma
```

In order to enable the `cpu` controller in the child cgroup `my.slice` must enable from the parent cgroup by writing `+cpu` in `cgroup.subtree_control`:
```
$ printf "+cpu\n" | sudo tee /tmp/cgroup/user.slice/cgroup.subtree_control
+cpu
```
[Notes](https://kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#controllers):
* Enabling a controller in a cgroup indicates that the distribution of the target resource across its immediate children will be controlled
* Resources are distributed top-down and a cgroup can further distribute a resource only if the resource has been distributed to it from the parent
* As a controller regulates the distribution of the target resource to the cgroup’s children, enabling it creates the controller’s interface files in the child cgroups

After that let's check to see how the file interface changes:
```
$ cat /tmp/cgroup/user.slice/cgroup.subtree_control
cpu memory pids
$ cat /tmp/cgroup/user.slice/my.slice/cgroup.controllers
cpu memory pids
$ cat /tmp/cgroup/user.slice/my.slice/cgroup.subtree_control
```
The cpu controller is enable in both parent and child cgroups and the `cgroup.subtree_control` in our cgroup is empty.
Note that trying to enable the controllers for the subtree of our custom cgroup without child cgroups
will result in blocking it and trying for e.g. to migrate a process in it will trigger an error:
```
/tmp/cgroup/user.slice/my.slice/cgroup.subtree_control: Device or resource busy
```
In other words make sure that for the custom cgroup the file `cgroup.subtree_control` reads `empty`. At least with kernel version is `5.10.0`.
If this file shows any controllers just write back the controller list formatted as `-<controller name 1> -<controller name 2> ...`.

Let's read the current statistics:
```
$ cat /tmp/cgroup/user.slice/my.slice/cpu.stat
usage_usec 21730
user_usec 5959
system_usec 15771
nr_periods 0
nr_throttled 0
throttled_usec 0
```
Note, that `usage_usec`, `user_usec` and `system_usec` are always displayed and `nr_periods`, `nr_throttled` and `throttled_usec` are showed if the controller is enabled.

Next let's the files that we need to change in order to adjust the CPU utilization by this cgroup:
* `cpu.max` : a read-write two value file with the default value `max 100000` that represent the max bandwidth limit.
The bandwidth has the format `$MAX $PERIOD` and indicates that the group may consume up to $MAX cycles in each $PERIOD duration (microseconds).
```
$ cat /tmp/cgroup/user.slice/my.slice/cpu.max
max 100000
````
* `cpu.weight` : a read-write single value file with default value `100` and the values interval [0, 10000].
It proportionally distributes CPU cycles to active children.
```
$ cat /tmp/cgroup/user.slice/my.slice/cpu.weight
100
```
Next we will see how to tune these parameters in order to lower the CPU utilization with a cpu intensive process:
```
$ cat /dev/random > /dev/null &
[1] 700705
$ printf "$!\n" | sudo tee /tmp/cgroup/user.slice/my.slice/cgroup.procs
700705
```
The job/process reads from `/dev/random` and writes to `/dev/null`. The last command just moves the process in our custom cgroup.
To visualize the CPU utilization of our cgroup relative to its sibling cgroups we will use `systemd-cgtop <parent cgroup>`:
```
$ systemd-cgtop user.slice
```
This will produce a dynamic view of the `user.slice` children:
```
systemd-cgtop --order=cpu -n 10 user.slice
```
We will allow to run the tool for `10` iterations and sort the view by cpu utilization.
With default cgrop parameters the view looks like this:
```
Control Group                                          		Tasks   %CPU   Memory  Input/s Output/s
user.slice                                                        298  199.5     3.1G        -        -
user.slice/my.slice                                                 1   99.9     4.0K        -        -
user.slice/user-1000.slice                                        297   99.7     2.9G        -        -
user.slice/user-1000.slice/session-48.scope                         7   99.5   549.6M        -        -
user.slice/user-1000.slice/user@1000.service                      272    0.1     2.2G        -        -
user.slice/user-1000.slice/user@1000.service/app.slice            146    0.1     1.9G        -        -
user.slice/user-1000.slice/user@1000.service/session.slice        124    0.0   277.5M        -        -
user.slice/user-1000.slice/session-2.scope                         14      -     8.6M        -        -
user.slice/user-1000.slice/session-886.scope                        4      -     2.6M        -        -
user.slice/user-1000.slice/user@1000.service/init.scope             2      -     2.5M        -        -
user.slice/user-1000.slice/user@1000.service/user.slice.slice       -      -     8.0K        -        -
```
Note that cgroup `my.slice` cpu utilization reaches 99.9% with a single process running in it.

Let's try to limit that with `cpu.weight` by changing the default value `100` to `1`:
```
$ printf "1\n" | sudo tee /tmp/cgroup/user.slice/my.slice/cpu.weight
1
```
The result looks like:
```
Control Group                                          		Tasks   %CPU   Memory  Input/s Output/s
user.slice                                                        297  199.3     3.1G        -        -
user.slice/user-1000.slice                                        296  104.8     2.9G        -        -
user.slice/user-1000.slice/session-48.scope                         7  104.9   540.2M        -        -
user.slice/my.slice                                                 1   94.5     4.0K        -        -
user.slice/user-1000.slice/user@1000.service                      271    0.1     2.2G        -        -
user.slice/user-1000.slice/user@1000.service/app.slice            145    0.1     1.9G        -        -
user.slice/user-1000.slice/user@1000.service/session.slice        124    0.0   277.5M        -        -
user.slice/user-1000.slice/session-886.scope                        4    0.0     2.6M        -        -
user.slice/user-1000.slice/session-2.scope                         14      -     8.6M        -        -
user.slice/user-1000.slice/user@1000.service/init.scope             2      -     2.5M        -        -
user.slice/user-1000.slice/user@1000.service/user.slice.slice       -      -     8.0K        -        -
```
The cpu utilization dropped _most of the time_ below `95%` and the cgroup `my.slice` was not the top cgroup by cpu utilization.
However this usually isn't enough since by the default value for `cpu.weight` is `100` and we dropped to the min value `1`.
Since the max value is `10000` using the min value doesn't make that much of difference.

If we want to fine tune the cpu utilization to a certain percent we must use the `cpu.max` file interface.
Let's revert the `cpu.weight` value back to `100` and modify the `cpu.max` to `1000 1000`.
Note that these value are lowest values possible on my test VM and they were found empirically by trying different values. 
```
$ printf "100\n" | sudo tee /tmp/cgroup/user.slice/my.slice/cpu.weight
100
$ echo "1000 1000" | sudo tee /tmp/cgroup/user.slice/my.slice/cpu.max
1000 1000
```
Now the top cgroup view of the `user.slice` looks a lot different:
```
Control Group                                          		Tasks   %CPU   Memory  Input/s Output/s
user.slice                                                        297  162.5     3.1G        -        -
user.slice/user-1000.slice                                        296  101.4     2.9G        -        -
user.slice/user-1000.slice/session-48.scope                         7  101.9   540.1M        -        -
user.slice/my.slice                                                 1   60.8     4.0K        -        -
user.slice/user-1000.slice/user@1000.service                      271    0.1     2.2G        -        -
user.slice/user-1000.slice/user@1000.service/app.slice            145    0.1     1.9G        -        -
user.slice/user-1000.slice/user@1000.service/session.slice        124    0.1   277.5M        -        -
user.slice/user-1000.slice/session-2.scope                         14      -     8.6M        -        -
user.slice/user-1000.slice/session-886.scope                        4      -     2.6M        -        -
user.slice/user-1000.slice/user@1000.service/init.scope             2      -     2.5M        -        -
user.slice/user-1000.slice/user@1000.service/user.slice.slice       -      -     8.0K        -        -
```
Now we see that the cpu utilization dropped to `60%`.
If the continue to increase the `$PERIOD` we get lower cpu utilization, as we can see in the below table:

| cpu.max | %CPU avg.
:--- | ---:| 
|1000 1000| 60 |
|1000 1500| 55 |
|1000 2000| 35 |
|1000 3000| 30 |
|1000 4000| 25 |
|1000 5000| 20 |
|1000 10000| 10 |
|1000 20000| 5 |

One more thing to note are the `cpu.stat`. Here are the statistics for the `cpu.max` set to `1000 20000` (cycles microseconds):
```
$ cat /tmp/cgroup/user.slice/my.slice/cpu.stat
usage_usec 3145217690
user_usec 10667527
system_usec 3134550163
nr_periods 1028445
nr_throttled 705368
throttled_usec 1814919413
```
If we try to read again the `cpu.stat` we'll get incremented values which mean the cgroup is heavily suppressed by the cpu controller.  

#### References
* [cgroup v2 admin guide](https://kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#)
* [archLinux wiki Cgroups](https://wiki.archlinux.org/title/Cgroups)
* [redhat Using Control Groups](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/resource_management_guide/chap-using_control_groups)

