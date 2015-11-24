#!/bin/sh
set -e

ec2_instance_id=`curl http://169.254.169.254/latest/meta-data/instance-id`
ecs_local_endpoint="ecs-agent:51678/v1"
ecs_cluster=`http_proxy= https_proxy= curl http://${ecs_local_endpoint}/metadata | jq -r .Cluster`
container_instance_arn=`http_proxy= https_proxy= curl http://${ecs_local_endpoint}/metadata | jq -r .ContainerInstanceArn | cut -d / -f2`

# deregister myself from ECS cluster
aws ecs deregister-container-instance \
    --region=$AWS_REGION \
    --cluster $ecs_cluster \
    --container-instance $container_instance_arn \
    --force
echo "Deregistered from $ecs_cluster"

# detach myself from ELBs

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
