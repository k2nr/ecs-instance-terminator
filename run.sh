#!/bin/sh

ec2_instance_id=`curl http://169.254.169.254/latest/meta-data/instance-id`
ecs_local_endpoint="ecs-agent:51678/v1"
ecs_cluster=`http_proxy= curl http://${ecs_local_endpoint}/metadata | jq .Cluster`
container_instance_arn=`http_proxy= curl http://${ecs_local_endpoint}/metadata | jq .ContainerInstanceArn`

# deregister myself from ECS cluster
aws ecs deregister-container-instance --cluster $ecs_cluster --container-instance $container_instance_arn
echo "Deregistered from $ecs_cluster"

# detach myself from ELBs

# stop ECS tasks
echo "Stopping docker containers..."
docker stop --time=30 $(docker ps -q)

# wait for tasks to be stopped
sleep 30

# terminate myself
echo "Terminating the instance..."
aws ec2 terminate-instances --instance-ids $ec2_instance_id
