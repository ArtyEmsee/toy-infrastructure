#!/bin/bash
export GCLOUD_ZONE=us-east1-b
export PROKECT_NS=civis-demo
export APP_ENV=master

# CREATE CLUSTER AND ADD TO KC
# authenticates machine through google cloud sdk, gcloud cli required
gcloud auth login
# advisorconnect-1238 is the project id for advisorconnect's google cloud platform environment
gcloud config set project advisorconnect-1238
# creates cluster and applies gcloud resource, as well defines the type of machine to be used for nodes
# type of machine defaults to n1-standard-1 (REVISIT)
gcloud container clusters create toy-cluster -z ${GCLOUD_ZONE} -m n1-standard-1
# gcloud goes and 
gcloud container clusters get-credentials toy-cluster

#CREATE PERSISTANT DRIVES
gcloud compute disks create civis-postgres-cluster-data-1 --size=20GB --type=pd-ssd --zone=${GCLOUD_ZONE}
gcloud compute disks create civis-postgres-cluster-data-2 --size=20GB --type=pd-ssd --zone=${GCLOUD_ZONE}
gcloud compute disks create civis-postgres-cluster-data-3 --size=20GB --type=pd-ssd --zone=${GCLOUD_ZONE}

# #BUILD BASE IMAGES
# cd ./docker/python3 && bash build.sh && cd ../..
# cd ./docker/node6 && bash build.sh && cd ../..
# cd ./flask-app && bash build.sh && cd ../

#K8S SETUP
kubectl create namespace ${PROKECT_NS}
kubectl create namespace civis-${APP_ENV}
kubectl create -f ./k8s/00-persistant-volumes.yaml
kubectl create -f ./k8s/01-persistant-volume-claim.yaml
kubectl create -f ./k8s/02-services.yaml
kubectl create -f ./k8s/03-secrets.yaml
kubectl create -f ./k8s/04-postgres-deployment.yaml
kubectl create -f ./k8s/05-redis-deployment.yaml

#PORT FOWARD POSTGRES
kubectl port-forward $(kc get pod --namespace=${PROKECT_NS} | grep civis-demo-postgres | head -n1 | awk '{print $1}') -n ${PROKECT_NS} 5432:5432

bash ./db_init.sh

# create database and user
cd flask-app && python manage.py db init && cd ../
cd flask-app && python manage.py db migrate && cd ../
cd flask-app && python manage.py db upgrade && cd ../

#CREATE APP
kubectl create -f ./k8s/${APP_ENV}/00-flask-app-secrets.yaml
kubectl create -f ./k8s/${APP_ENV}/01-flask-app-service.yaml
kubectl create -f ./k8s/${APP_ENV}/02-flask-app-deployment.yaml
kubectl create -f ./k8s/${APP_ENV}/03-flask-app-hpa.yaml








#CLEANUP
# gcloud auth login
# gcloud config set project advisorconnect-1238
kubectl config unset users.$(kubectl config view -o json | jq .users |  grep gke_civis-demo | tr -d '"' | tr -d ',' | sed -e 's/.*://' | tr -d '[:space:]')
kubectl config unset contexts.$(kubectl config view -o json | jq .contexts |  grep name | grep gke_civis-demo | tr -d '"' | tr -d ',' | sed -e 's/.*://' | tr -d '[:space:]')
kubectl config unset clusters.$(kubectl config view -o json | jq .clusters  |  grep gke_civis-demo | tr -d '"' | tr -d ',' | sed -e 's/.*://' | tr -d '[:space:]')
gcloud container clusters delete toy-cluster
