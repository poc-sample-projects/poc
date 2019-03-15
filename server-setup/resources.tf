# Deploys the public ssh key into the servers at build time, ensure the key is available.

resource "digitalocean_ssh_key" "ssh" {
    name = "SSH key"
    public_key = "${file("files/do_key.pub")}"
}



# Deploys the servers on digital ocean and does some prep work as defined by the provisioner.

resource "digitalocean_droplet" "kube" {
    count = "${var.server_count}"
    image = "${var.os_build}"
    name = "kube-server-${count.index}"
    region = "${var.region}"
    size = "${var.server_size}"
    ssh_keys = ["${digitalocean_ssh_key.ssh.id}"]

    provisioner "remote-exec" {
        inline = [
            "yum -y install vim epel-release"
        ]
    }

    connection {
        type = "ssh"
        user = "root"
        private_key = "${file("secrets/do_key")}"
    }
}
