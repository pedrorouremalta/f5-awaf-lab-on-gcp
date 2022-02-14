# f5-awaf-lab-on-gcp

This is a small step by step guide on how to build a F5 AWAF (Advanced Web Application Firewall) lab environment on GCP (Google Cloud Platform). The purpose of this guide is to provide an easy way for quickly spin up a lab environment which can be used for study or demo purposes. 

*Note: The guide was written to be easily followed from any Linux distro. However all of linux-specific commands can be easily converted to other operating systems like Windows or Mac.* 

## Overview

This is high-level view about he steps performed by this guide:

    1. Create all the network infrastructure needed (networks, subnets, firewall rules, forwarding rules ...);
    2. Create a VM (named "vulnerable-apps") using the Container-Optimized OS in which 4 vulnerable apps (available as container images) will be deployed;
    3. Create a BIG-IP Standalone VM with 3-NICs using PAYG; 
    4. Post an AS3 declaration which will deploy all 4 vulnerable apps on BIG-IP; 

## Vulnerable Apps 

These are the vulnerable apps which will be deployed in the lab environment (with the credentials):

1. JuiceShop (credentials should be discovered, this is one of challenges);
2. DVWA (admin/password);
3. Hackazon (admin/hackmesilly);
4. WebGoat (credentials available on the login page);

## Building an F5 AWAF lab environment (step-by-step)

1. Define some environment variables:
    ```
    export PROJECTNAME="f5-awaf-lab-001"
    export REGION="us-central1"
    export ZONE="us-central1-a"
    ```

2. Create a GCP project: 
    ```
    gcloud projects create $PROJECTNAME --name="My F5 AWAF Lab" 
    ```
3. Configure the newly created project as the default project:
    ```
    gcloud config set project $PROJECTNAME
    ```
4. Get the billing account ID which will be used by this project: 
    ```
    gcloud alpha billing accounts list
    ```

5. Link the newly created project with your billing account :
    ```
    gcloud alpha billing projects link $PROJECTNAME --billing-account XXXXXX-XXXXXX-XXXXXX
    ```

6. Get your public IP and save it in an environment variable (this public IP will be used to restrict the access to your lab environment): 
    ```
    export MYIP=$(curl api.ipify.org)
    ```
7. Enable some GCP APIs that will be used later on:
    ```
    gcloud services enable compute.googleapis.com 
    gcloud services enable deploymentmanager.googleapis.com
    ```
8. Delete the default network and firewall rules (just for cleanup, this step is optional):
    ```
    gcloud compute firewall-rules delete default-allow-icmp --quiet
    gcloud compute firewall-rules delete default-allow-internal --quiet
    gcloud compute firewall-rules delete default-allow-rdp --quiet
    gcloud compute firewall-rules delete default-allow-ssh --quiet
    gcloud compute networks delete default --quiet
    ```

9. Create 3 VPC networks (external,internal,management):
    ```
    gcloud compute networks create net-external --subnet-mode=custom
    gcloud compute networks create net-internal --subnet-mode=custom
    gcloud compute networks create net-management --subnet-mode=custom
    ```

10. Create 3 subnets (one for each VPC created in the previous step):

    ```
    gcloud compute networks subnets create subnet-external --network=net-external --range=10.10.0.0/16 --region=$REGION
    gcloud compute networks subnets create subnet-internal --network=net-internal --range=172.16.0.0/16 --region=$REGION
    gcloud compute networks subnets create subnet-management --network=net-management --range=192.168.1.0/24 --region=$REGION
    ```

11. Generare a SSH key pair (which will be used to access your environment):
    ```
    ssh-keygen -f mykey
    echo "admin:$(cat mykey.pub)" > mykey_gcp.pub
    ```


12. Upload the public key to the project metadata (the corresponding private key will be used to login in the VMs):
    ```
    gcloud compute project-info add-metadata --metadata-from-file=ssh-keys=./mykey_gcp.pub
    ```

13. Create the Virtual Machine which will host the vulnerables apps:

    ```
    gcloud compute instances create vulnerable-apps --image cos-stable-93-16623-39-28 --image-project cos-cloud  --zone $ZONE --machine-type e2-medium --network-interface subnet=subnet-internal,private-network-ip=172.16.0.51 --tags vulnerable-apps --metadata-from-file=startup-script=./vulnerable-apps.sh
    ```
    **Note:** The vulnerables apps can take too long to start because of the container images pulling.

14. Get the public IP of the "vulnerable-apps" VM created in the previous step:

    ```
    export VULNAPPSIP=`gcloud compute instances describe vulnerable-apps --format='get(networkInterfaces[0].accessConfigs[0].natIP)' --zone $ZONE`
    ```
    
15. Create the firewall rule which will allow the access to the VM (and applications) deployed in the previous step:

    ```
    gcloud compute firewall-rules create fw-rule-allow-vulnerable-apps --direction=INGRESS --priority=1000 --network=net-internal --action=ALLOW --rules=tcp:22,tcp:9000-10000 --source-ranges=$MYIP,172.16.0.0/16 --target-tags=vulnerable-apps
    ```

16. Log in the "vulnerale-apps" VM and check whether all vulnerables apps are available (optional): 

    ```
    ssh -i mykey admin@$VULNAPPSIP
    watch "docker ps"
    <CTRL+C> <when all applications are available>
    exit
    ```
17. Clone F5 GDM templates repository:

    ```
    git clone https://github.com/F5Networks/f5-google-gdm-templates.git
    ```

18. Copy the needed templates files to your current directory (we will the deploy a BIG-IP Standalone with 3-NICs using PAYG): 

    ```
    cp f5-google-gdm-templates/supported/standalone/3nic/existing-stack/payg/* .
    ```

19. Configure the GDM template: 

    ```
    sed -i "s/region:/region: $REGION/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/availabilityZone1:/availabilityZone1: $ZONE/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/mgmtNetwork:/mgmtNetwork: net-management/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/mgmtSubnet:/mgmtSubnet: subnet-management/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/restrictedSrcAddress:/restrictedSrcAddress: $MYIP/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/restrictedSrcAddressApp:/restrictedSrcAddressApp: $MYIP/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/network1:/network1: net-external/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/subnet1:/subnet1: subnet-external/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/network2:/network2: net-internal/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/subnet2:/subnet2: subnet-internal/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/instanceType: n1-standard-4/instanceType: e2-standard-8/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/applicationPort: 443/applicationPort: 80/" f5-existing-stack-payg-3nic-bigip.yaml
    sed -i "s/bigIpModules: ltm:nominal/bigIpModules: ltm:nominal,asm:nominal/" f5-existing-stack-payg-3nic-bigip.yaml
    ```

20. Deploy the GDM template:

    ```
    gcloud deployment-manager deployments create f5-awaf-lab --config f5-existing-stack-payg-3nic-bigip.yaml
    ```
    **Note:** The BIG-IP can take up to 8 min to became available. 

21. Get the BIG-IP public management IP :

    ```
    export BIGIP=`gcloud compute instances describe bigip1-f5-awaf-lab --format='get(networkInterfaces[1].accessConfigs[0].natIP)' --zone $ZONE`
    ```

22. Log in the BIG-IP using the private key created previously and change the admin's password: 

    ```
    ssh -i mykey admin@$BIGIP
    modify /auth user admin password "F5training@123"
    save sys config
    quit
    ```

23. Create a target instance (which points to the BIGIP VM instance):

    ```
    gcloud compute target-instances create bigip1-target-instance --instance=bigip1-f5-awaf-lab
    ```

24. Create 4 forwarding rules (one for each application):
    ```
    gcloud compute forwarding-rules create forwarding-rule-1 --ip-protocol=TCP --load-balancing-scheme=EXTERNAL --network-tier=PREMIUM --ports=80 --target-instance=bigip1-target-instance
    gcloud compute forwarding-rules create forwarding-rule-2 --ip-protocol=TCP --load-balancing-scheme=EXTERNAL --network-tier=PREMIUM --ports=80 --target-instance=bigip1-target-instance
    gcloud compute forwarding-rules create forwarding-rule-3 --ip-protocol=TCP --load-balancing-scheme=EXTERNAL --network-tier=PREMIUM --ports=80 --target-instance=bigip1-target-instance
    gcloud compute forwarding-rules create forwarding-rule-4 --ip-protocol=TCP --load-balancing-scheme=EXTERNAL --network-tier=PREMIUM --ports=80 --target-instance=bigip1-target-instance

25. Get the public IPs which will be used by the vulnerable applications: 

    ```
    export JUICESHOP_IP=`gcloud compute forwarding-rules list --filter="name=('forwarding-rule-1')" --format="value(IPAddress)"`
    export DVWA_IP=`gcloud compute forwarding-rules list --filter="name=('forwarding-rule-2')" --format="value(IPAddress)"`
    export HACKAZON_IP=`gcloud compute forwarding-rules list --filter="name=('forwarding-rule-3')" --format="value(IPAddress)"`
    export WEBGOAT_IP=`gcloud compute forwarding-rules list --filter="name=('forwarding-rule-4')" --format="value(IPAddress)"`

26. Ajust the AS3 declaration (which will be used to deploy the vulnerable apps): 

    ```
    sed "s/A.A.A.A/$JUICESHOP_IP/" vulnerable-apps.original.json > vulnerable-apps.json
    sed -i "s/B.B.B.B/$DVWA_IP/" vulnerable-apps.json
    sed -i "s/C.C.C.C/$HACKAZON_IP/" vulnerable-apps.json
    sed -i "s/D.D.D.D/$WEBGOAT_IP/" vulnerable-apps.json
    ```

27. Post the AS3 declaration:

    ```
    curl -u "admin:F5training@123" -kv -X POST https://$BIGIP/mgmt/shared/appsvcs/declare -d @vulnerable-apps.json
    ```

28. Get the BIG-IP Configuration Utility URL:

    ```
    echo "Configuration Utility - https://$BIGIP/"
    ```

29. Get the vulnerable apps URLs:

    ```
    echo "JuiceShop - http://$JUICESHOP_IP/"
    echo "DVWA - http://$DVWA_IP/"
    echo "Hackazon - http://$HACKAZON_IP/"
    echo "WebGoat - http://$WEBGOAT_IP/WebGoat/"
    ```

## Cleaning up the lab environment (step-by-step)

1. Delete the forwarding rules: 

    ```
    gcloud compute forwarding-rules delete forwarding-rule-1 --quiet
    gcloud compute forwarding-rules delete forwarding-rule-2 --quiet
    gcloud compute forwarding-rules delete forwarding-rule-3 --quiet
    gcloud compute forwarding-rules delete forwarding-rule-4 --quiet
    ```

2. Delete the target instance: 

    ```
    gcloud compute target-instances delete bigip1-target-instance --quiet
    ```

3. Delete the BIG-IP deployment:

    ```
    gcloud deployment-manager deployments delete f5-awaf-lab --delete-policy=DELETE --quiet
   
    ```

4. Delete the "vulnerable-apps" VM: 

    ```
    gcloud compute instances delete vulnerable-apps --quiet
    ```

5. Delete the remaining firewall rule:

    ```
    gcloud compute firewall-rules delete fw-rule-allow-vulnerable-apps --quiet
    ```

6. Delete the 3 subnets:

    ```
    gcloud compute networks subnets delete subnet-external --quiet
    gcloud compute networks subnets delete subnet-internal --quiet
    gcloud compute networks subnets delete subnet-management --quiet
    ```

7. Delete the 3 VPC networks:

    ```
    gcloud compute networks delete net-external --quiet
    gcloud compute networks delete net-internal --quiet
    gcloud compute networks delete net-management --quiet
    ```

8. Delete the F5 GDM templates repository cloned and other files:

    ```
    rm -rf ./f5-google-gdm-templates/
    rm f5-existing-stack-payg-3nic-bigip.*
    rm vulnerable-apps.json
    ```