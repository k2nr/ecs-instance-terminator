#!/bin/sh
set -e

ec2_instance_id=`curl http://169.254.169.254/latest/meta-data/instance-id`
ecs_agent_ip=`curl --unix-socket /var/run/docker.sock http:/containers/ecs-agent/json | jq -r .NetworkSettings.IPAddress`
no_proxy=$no_proxy,$ecs_agent_ip
ecs_local_endpoint="$ecs_agent_ip:51678/v1"
ecs_cluster=`curl http://${ecs_local_endpoint}/metadata | jq -r .Cluster`
container_instance_arn=`curl http://${ecs_local_endpoint}/metadata | jq -r .ContainerInstanceArn | cut -d / -f2`

echo EC2 instance ID: $ec2_instance_id
echo ECS cluster: $ecs_cluster
echo ECS Container Instance ARN: $container_instance_arn

# deregister myself from ECS cluster
aws ecs deregister-container-instance \
    --region=$AWS_REGION \
    --cluster $ecs_cluster \
    --container-instance $container_instance_arn \
    --force
echo "Deregistered from $ecs_cluster"

# Deregister myself from ELBs
elb_names=`aws elb describe-load-balancers --region $AWS_REGION | jq -r ".LoadBalancerDescriptions | map(select(contains({Instances: [{InstanceId: \"$ec2_instance_id\"}]}))) | map(.LoadBalancerName) | join(\" \")"`

echo $elb_names

for elb in $elb_names
do
    echo "Deregistering the instance from $elb"
    aws elb deregister-instances-from-load-balancer --region $AWS_REGION --load-balancer-name $elb --instances $ec2_instance_id
done

while [[ -n "$elb_names" ]]
do
    sleep 5
    echo $elb_names
    echo "Waiting for the instance to be deregistered"
    elb_names=`aws elb describe-load-balancers --region $AWS_REGION | jq -r ".LoadBalancerDescriptions | map(select(contains({Instances: [{InstanceId: \"$ec2_instance_id\"}]}))) | map(.LoadBalancerName) | join(\" \")"`
done

# stop ECS tasks
echo "Stopping docker containers..."

## Do not kill myself
myid=`cat /proc/self/cgroup | grep 'docker' | sed 's/^.*\///' | tail -n1`
container_ids=`curl --unix-socket /var/run/docker.sock http:/containers/json | jq -r "map(select(.Id != \"$myid\")) | map(.Id) | join(\" \")"`

for container_id in $container_ids
do
    curl -XPOST --unix-socket /var/run/docker.sock http:/containers/$container_id/stop?t=$STOP_TIMEOUT
done

# wait for tasks to be stopped
sleep $STOP_TIMEOUT

# terminate myself
echo "Terminating the instance..."
aws ec2 terminate-instances --region=$AWS_REGION --instance-ids $ec2_instance_id
