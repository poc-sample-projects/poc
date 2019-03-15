# Scalable wordpress setup

This setup is made out of 4 parts similar to the folder structure of the project.
 - 1 . Server deployment and base configuration
 - 2 . Docker. Kubernetes cluster setup and Helm installation
 - 3 . Database cluster setup for high availability and scaling
 - 4 . WordPress deployment 


### Server Deployment [server-setup]
*For this setup we will need an ssh key and terraform installed - refer to [https://learn.hashicorp.com/terraform/getting-started/install.html](https://learn.hashicorp.com/terraform/getting-started/install.html) for a quick guide on how to get started.*

The server setup files can be found inside the **server-setup** folder.
- provider.tf -> defines the provider module to be used by terraform, in our case Digital Ocean.
- resources.tf -> defines the resource that terraform will create.
- variables.tf -> set of variables to allow more flexibility when deploying multiple resources.
- prod_vars.tfvars -> *key=value* file that pre-assigns values to the variables for a more automated setup.
- files -> you need to place your public ssh key in this folder and update the resources.tf with the key name
- secrets -> you need to add your private key here and update the resources.tf with the key name

By default it will deploy 3 servers with 1vCpu, 2GB Ram and 50Gb of storage.

To deploy the server run the following command:
`terraform plan -var-file=prod_vars.tfvars`

Review the output to ensure you are happy with what is going to be created, and the run:
`terraform apply -var-file=prod_vars.tfvars`

At the end of the setup you should now have 3 deployed server and some initial packages installed that will be necessary on the next steps.

### Setting up Docker, the Kubernetes cluster and Helm package manager
*For this step you need Ansible installed, if you don't have Ansible installed you can follow this document - [https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)*
This also assumes you have your private key setup for auth against the servers.

The configuration files for this step can be found in the **kube-cluster** folder:
- hosts -> use the IPs from the Digital Ocean dashboard to create your hosts- for this setup we have a master and two agents.
- dependencies.yml -> Playbook to install all the required dependecies for the kubernetes cluster.
- master.yml -> configures the master node of the cluster
- agents.yml -> configures the agent nodes or slave nodes, and joins them into the cluster.
- rbac-config.yaml - prep for a secure auth needed by Helm Tiller.
- helm_setup.sh -> installs the helm package manager both the client and the server (tiller). *Note: for this step you need to copy the contents of /etc/kubernetes/admin.conf  from the master node, create a directory called .kube and your $HOME, inside that folder create a file called config and past the content, this allows you to connect to the cluster from your local machine, ensure you have kubectl installed locally*

First run:
`ansible-playbook -i hosts dependencies.yml`
This will set you up with base for the configuration of the kubernetes cluster.

To setup the master run:
`ansible-playbook -i hosts master.yml`

Setup the agents:
`ansible-playbook -i hosts agents.yml`

if you run `# kubectl get nodes`you should see a similar output as below:

`NAME            STATUS   ROLES    AGE   VERSION`
`kube-server-0   Ready    master   23h   v1.10.12`
`kube-server-1   Ready    <none>   23h   v1.10.12`
`kube-server-2   Ready    <none>   23h   v1.10.12`

Setup Helm:

Run `./helm_setup`
it should output something similar to this
`Run 'helm init' to configure helm.`

Before we run `helm init` lets setup the RBAC .
Run `kubectl create -f rbac-config.yaml` this will create a service account for us to use with Tiller
We can now run `helm init --service-account tiller --history-max 200`
To confirm Tiller was installed and initialised you can run `kubectl get pods --namespace kube-system`

### Database Cluster setup

The configuration files for this step are located in the **database-setup** folder:
- db-pv.yml -> creates persistent volumes to be used by the database to store the data and persist in case of pod failure.
-values.yml - this file includes the default values for Percona XtraDB cluster and is where we define the password for both the root, the replication and the normal user that we will use with wordpress

To setup the database cluster we need to start by creating the Persistent Volumes and for that run:
`kubectl create -f db-pv.yml`
This will create 3 Persistent Volumes to be used by the database cluster nodes

*Note: you will need a new persistent volume if you want to scale the cluster. Example: if you want to scale the cluster by 5 which means adding more 2 nodes you need to create 2 new persistent volumes*

Now that we have our PVs we can go ahead and use Helm to deploy our cluster using the values.yml file we setup before:
`helm install --name wp-db-cluster -f values.yaml stable/percona-xtradb-cluster`

On the output will get all details including the DNS name you can use to connect to database server on port 3306 from within the cluster.

### Wordpress setup
the WordPress config files are located inside the **wordpress-setup** folder:
- wordpress.yml -> configuration to deploy a scalable WordPress install.

This is a proof of concept on a production ready we would use an external loadbalancer to expose the service and also do ssl termination.

This spec will create a deployment with 3 replicas, it has a persistent volume that is read/write accessible by all pods, this allow for the data to be the same independently of how many pods we scale the application. 
Ideally this mount would be a NFS share or any other type of shared storage,

before deploying change the IP address located on line 10 to the external IP of you master node for example.
`  externalIPs:`
`   - 167.99.92.225`

To deploy run: `Kubectl create -f wordpress` and give it a minute or two to deploy.

you can now access your WordPress install on the IP you defined.


### Scaling the Kubernetes Cluster

If you need to scale number of agents you can go into the **kube-cluster** folder and add the new servers on the hosts file below the `[agents]` role.

Then just run `ansible-playbook -i hosts dependecies.yml` to configure the new hosts and running`ansible-playbook -i hosts agents.yml`it will all the new hosts to the cluster.

If you run `kubectl get nodes` you should now see the new nodes available to be used by the cluster.

### Scaling the Database cluster

As mentioned on the database cluster config section, to scale the nodes you need to scale the persistent volumes.

Open the db-pv.yml file and add a new Persistent volume at the end, you can use the code of a existent PV as a template, just ensure the name and path are unique from the existing ones.
Then run: `kubectl apply -f db-pv.yml`this will create the new PV's and we can now scale the service.

If you don't recall the name of the cluster you can always run:
`kubectl get statefulsets` to fin the cluster name.

Now lets scale it, to scale by two run `kubectl scale statefulset/wp-db-cluster-pxc --replicas=5`
If you run `kubectl get pods` you will see the two new pods being created adding for a total of 5 pods.

To scale down by two is the same process `kubectl scale statefulset/wp-db-cluster-pxc --replicas=3`

### Scaling the Wordpress install

To scale the WordPress install its similar to the database scaling without the need to setup new PV's

To scale the WordPress install by 2 just run `kubectl scale deployment wordpress --replicas=5`

After that you should see the two new replicas being added. the output should be similar to this:
`# kubectl get pods`
`NAME                         READY   STATUS    RESTARTS   AGE`

`wordpress-7b5b4c7877-5kqqq   1/1     Running   0          55s`

`wordpress-7b5b4c7877-ccs9g   1/1     Running   0          55s`

`wordpress-7b5b4c7877-cl4j8   1/1     Running   0          9s`

`wordpress-7b5b4c7877-m5h6g   1/1     Running   0          55s`

`wordpress-7b5b4c7877-zwb4l   1/1     Running   0          9s`

`wp-db-cluster-pxc-0          2/2     Running   0          22h`

`wp-db-cluster-pxc-1          2/2     Running   0          22h`

`wp-db-cluster-pxc-2          2/2     Running   0          22h`

To downscale it by two is the same as before `kubectl scale deployment wordpress --replicas=3` this will bring it back to 3 pods.
