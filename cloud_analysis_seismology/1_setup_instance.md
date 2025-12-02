# EC2 + Docker + Jupyter + S3

This tutorial will walk you thought getting on an AWS cloud instance from the ground up.

## AWS web console access

* Login to [Cloudbank](https://cloudbank.org)
* From the dashboard click on "Access Cloudbank Billing Accounts"
* On the "Amazon Web Services" billing account, click on the `Login` button under "Public Cloud Web Console Login"

### Choosing a region
An important aspect of cloud is that the computing and data centers are distributed around the world and labeled as "regions". For fastest connection to data storage on S3, we recommend to choose the region where the data is. To choose a region in AWS, follow these steps:

1. Log in to your AWS Management Console.
2. In the top-right corner, click on the current region name (e.g., US East (N. Virginia)).
3. In the dropdown menu that appears, select a region (for this tutorial let's use US West (Oregon)).
4. After selecting the region, all AWS services you use will be hosted in that region.

### Creating a security group to grant external access to an instance

### How to Create an EC2 Security Group with SSH (22), HTTP (80), and HTTPS (443)

Open the EC2 Console  
AWS Console → **EC2**

Go to “Security Groups”  
Left sidebar → **Network & Security → Security Groups**

Click **Create security group**

Basic Details  
- Security group name: `web-ssh-access`  
- Description: `Allow SSH and HTTP`

Add Inbound Rules  
Click **Add rule** three times, for source select `Anywhere-IPv4`:

| Type | Protocol | Port | Source |
|------|----------|------|--------|
| SSH  | TCP      | 22   | `0.0.0.0/0` |
| HTTP | TCP      | 80   | `0.0.0.0/0` |
| HTTPS | TCP     | 443  | `0.0.0.0/0` |

Leave Outbound Rules as default (All traffic allowed)

Click **Create security group**

Attach the Security Group to an EC2 Instance  
- When launching a new instance, choose **Select existing security group** and pick `web-ssh-access`  
- For an existing instance:  
    Actions → Networking → Change security groups → select `web-ssh-access` → Save

Your instance now allows SSH on port 22 and HTTP on port 80.

### Launching an instance
Launch an instance using **EC2 (Elastic Computing Cloud)**. Follow the steps below.

1. In the AWS Management Console, search and navigate to the **EC2** dashboard using the `Search` box on the top.
2. Click on **Launch Instance** to start the process of creating a new EC2 instance.
4. **Application and OS Image**: Choose the default ``Amazon linux``.
5. **Instance Type**: This specifies the RAM, vCPU, network, etc. `t2.xlarge` is recommended for this tutorial.
6. **Key Pair**: Create a new key pair, or specify an existing one. Download the `.pem` file, move it to a location that you can have access to and remember where it is. 
   
    > **Note:**
    > * If the file does not save as `.pem`, replace the extension with `.pem`.
    > * For Windows users, download the type ED25519 and the `.ppk` file.
    > * You can re-use the key created previously, if you still have access to that file.

7. **Network Settings**: Select existing security group -> Select security group -> Select `web-ssh-access`. This allows traffics in and out of the instance and is required for SSH (port 22) and Jupyter lab connection.
8. **Configure Storage**: Add more storage to your instance. 20 GiB will be sufficient for this tutorial.
9. **Launch instance** with the current configuration. Wait until the instance showing a `Running` state on the console.
10. **Connect to the instance**: AWS provides web-based connection where you don't need to have a SSH client installed. Click on your instance -> Connect -> EC2 Instance Connect.
    
    > **Note:**
    > There are alternative ways connecting to the instance using the SSH client installed on your laptop.
    >
    > a. On **Linux/macOS**, copy the ssh link command in the folder where the PEM file is below and ssh to the instance. Be sure to change the permission of the key file so that it is only readable to you. You only need to do it once.
    >
    > ```bash
    > chmod 400 file.pem
    >
    > ssh -i "file.pem" ec2-user@Your-Public-IPv4-DNS
    > ```
    >
    > b. On **Windows**, login to an EC2 instance using **PuTTY** (a free SSH client):
    > * Open PuTTY. On the PuTTY Configuration screen, click Session in the Category pane.
    > * In the Host Name (or IP address) box, paste ``ec2-user@Your-Public-IPv4-DNS``. Your public IPv4 DNS can be found in the details of your EC2 instance.
    > * Make sure Connection type: SSH is clicked
    > * Back in the Category pane, expand Connection, expand SSH, and click Auth.
    > * In the Private key file for AUTH/Credentials box, click browse and locate your ``.ppk`` file for the instance that you created and click. Depending on the version of Putty, 
    > * Now click open and accept the connection.

## Environment Configuration
As you may notice, the EC2 you just launched has no user-specific software installed at all. Next we will configure the computing environment using a Docker container.

1. To install docker, run the following command.

    ```bash
    sudo yum install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    docker --version

    # Upon successful installation, you would see:
    # Docker version xx.x.x, build xxxxx
    ```

2. Pull the image. This will pull the Docker image named `seisscoped/seis_cloud` from the GitHub Container Registry.
    ```bash
    sudo docker pull ghcr.io/seisscoped/seis_cloud:centos7_jupyterlab
    ```

3. Run the docker image as container (with HTTPS). This launches Jupyter Lab inside the container, forwards container port 8888 to port 80 on the EC2 instance, and enables HTTPS using a self-signed certificate tied to the instance Public DNS. Copy the *Public DNS (IPv4)* from the EC2 console, export it, and create the certificate pair:

    ```bash
    export URL="ec2-xxx-x-xxx-xx.us-west-2.compute.amazonaws.com"  # replace with your Public DNS

    mkdir -p /home/ec2-user/jupyter-cert
    cd /home/ec2-user/jupyter-cert

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout jupyter.key -out jupyter.crt \
      -subj "/CN=${URL}"
    ```

    Start the container and mount the certificate directory so Jupyter Lab can serve HTTPS:

    ```bash
    docker run -p 443:8888 --rm -it \
        --user $(id -u ec2-user):$(id -g ec2-user) \
        -v /home/ec2-user:/home/scoped \
        -v /home/ec2-user/jupyter-cert:/home/scoped/jupyter-cert \
        -e HOME=/home/scoped \
        ghcr.io/seisscoped/noisepy:centos7_jupyterlab \
        jupyter lab --no-browser --ip=0.0.0.0 \
            --IdentityProvider.token=scoped \
            --certfile=/home/scoped/jupyter-cert/jupyter.crt \
            --keyfile=/home/scoped/jupyter-cert/jupyter.key
    ```

An EC2 instance has two IP addresses: one for the AWS internal networking system, one open to the public. To access the notebook, you need to connect on the public IP address. Open a browser, type the Public IPv4 DNS of the instance, and navigate to `https://Your-Public-IPv4-DNS`. Because the certificate is self-signed you will see a browser warning—proceed after confirming the certificate details.

You will be prompted for a token. Please enter `scoped` (case sensitive), as we specified in `--IdentityProvider.token=scoped` argument.

## Save the virtual image (optional)

You can save the image (AMI) so that you can start from there next time. This can save time and effort in setting up the instance from scratch every time. Here are the steps to save the virtual image (AMI) of an EC2 instance in AWS:

In your AWS Management Console:
1. Navigate to the EC2 dashboard.
2. Select the EC2 instance that you want to save the image of.
3. Right-click on the instance and click on "Create Image" in the dropdown menu.
4. In the "Create Image" dialog box, enter a descriptive name for your image in the "Name" field.
5. Optionally, you can add a description and tags to the image for easier management later on.
6. Click on the "Create Image" button to start the image creation process.
7. Wait for the image creation process to complete. This may take several minutes depending on the size of your instance and the amount of data being saved.
8. Once the image has been created, it will appear in the "AMIs" section of the EC2 dashboard.

You have to save it every time you want to save the current state of the instance.

## Terminating an instance

What is the difference between stop and terminate and instance: saving data vs cost. If you stop, you do not pay for the hardware, but you will pay for the EBS volume only and the data is saved in the EBS volume. If you terminate, all data will be wiped and you will cease to pay.

 > **Note:**
 > Visit [here](https://docs.rightscale.com/faq/clouds/aws/Whats_the_difference_between_Terminating_and_Stopping_an_EC2_Instance.html) to read more about stopping vs terminating.