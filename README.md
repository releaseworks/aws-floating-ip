# AWS Floating IP
This repository provides a script for implementing active-passive failover with a Floating IP (also known as a Virtual IP or VIP) in AWS EC2.

The benefits and limitations of this approach are described in an AWS whitepaper: https://docs.aws.amazon.com/whitepapers/latest/real-time-communication-on-aws/floating-ip-pattern-for-ha-between-activestandby-stateful-servers.html

## Overview
For certain high-availability applications, you may want to implement an active-passive configuration using a floating IP address in AWS. In this scenario, clients would connect to the active application using a known floating IP address (eg. 192.168.1.100). In case of a failure of the primary application instance, the floating IP would get automatically reassigned to a secondary instance.

Please note that it's almost always better to use a load balancer (eg. Application Load Balancer or Network Load Balancer), but in some cases this might not be possible - for example if a high number of ports is needed.

## Quick start
1. Set up an Autoscaling Group using an AMI of your choice, for example Amazon Linux 2 comes with the prerequisites: AWS CLI, ifconfig, ping
2. Configure the User Data script to include the following (replace `192.168.1.100` with your desired floating IP):
```
curl -o /usr/sbin/aws_floating_ip https://raw.githubusercontent.com/releaseworks/aws-floating-ip/main/aws_floating_ip.sh
chmod 755 /usr/sbin/aws_floating_ip

aws_floating_ip 192.168.1.100 > /var/log/aws_floating_ip.log 2>&1 &
```
3. Create a new IAM Instance Profile with the following policy, and configure your autoscaling Launch Template to use it. This will allow the script to assign the floating IP to its primary network interface:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Action": "ec2:AssignPrivateIpAddresses",
            "Resource": "*"
        }
    ]
}
```

The script will check to see if the floating IP is responding to ping every 30-60 seconds. If the floating IP is responding, it is assumed to be healthy and no action is taken. If it is not responding, the script will try to assign the floating IP to the current instance as a secondary IP address.

The floating IP address should be in the same subnet as the primary IP of the instance(s).

## Troubleshooting
If you used the above snippet to start the script, logs will be output to `/var/log/aws_floating_ip.log`.

When troubleshooting, you may want to enable debug mode which gives you more output. This can be done by defining the DEBUG environment variable, eg: `DEBUG=1 aws_floating_ip 192.168.1.100`.

## Additional considerations
If you would like to enable external access to your private floating IP, you can assign a public Elastic IP to it. The Elastic IP will move with the private IP address.

This script is designed to work with an application that can withstand downtime of up to a few minutes. It also naively assumes that whatever application you are running is 'healthy' if the instance responds to ICMP ping.

Depending on your application, you may need additional reconfiguration to bind it to the virtual interface that is created by the script (by default `eth0:0`).

For commercial assistance, please reach out to Releaseworks cloud engineers via https://release.works.
