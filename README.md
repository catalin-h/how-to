# how-to
Cookbook with recipes for Linux, Docker, networking and debugging

* [How to create a UDP tunnel with socat](./socat_udp_tunnel.md)
* [How to set process limits with Linux cgroup v2](./cgroupv2_set_process_limits.md)
* [How DNS works on Docker](./how_dns_works_on_docker.md)
* [How to run Docker swarm overlay networks over ssh tunnel](./docker_swarm_over_ssh_tunnel.md)
	* [Prerequisites](./docker_swarm_over_ssh_tunnel.md#Prerequisites)
	* [Setup the ssh tunnel](./docker_swarm_over_ssh_tunnel.md#setup-the-ssh-tunnel)
	* [Enable swarm mode](./docker_swarm_over_ssh_tunnel.md#enable-swarm-mode)
	* [Working with overlay networks](./docker_swarm_over_ssh_tunnel.md#working-with-overlay-networks)
		* [Create the overlay network](./docker_swarm_over_ssh_tunnel.md#create-the-overlay-network)
		* [Overlay networks and VXLAN](./docker_swarm_over_ssh_tunnel.md#overlay-networks-and-vxlan)
		* [How to start- ebugging overlay network issues](./docker_swarm_over_ssh_tunnel.md#how-to-start-debugging-overlay-network-issues)
		* [Fixing the firewall configuration to permit the control and data plane communication](./docker_swarm_over_ssh_tunnel.md#fixing-the-firewall-configuration-to-permit-the-control-and-data-plane-communication)
		* [Start overlay communication](./docker_swarm_over_ssh_tunnel.md#start-overlay-communication)
	* [Open github issues ipv6 and docker swarm](./docker_swarm_over_ssh_tunnel.md#open-github-issues-ipv6-and-docker-swarm)
	* [References](./docker_swarm_over_ssh_tunnel.md#references)
