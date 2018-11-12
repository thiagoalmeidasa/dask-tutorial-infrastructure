cluster_name ?= dask-pycaxias-2018
name ?= $(cluster_name)
config ?= jhub-config.yaml
jhub_version ?= v0.7

# GCP settings
project_id ?= PROJECT_ID
zone ?= us-central1-b
num_nodes ?= 3
machine_type ?= n1-standard-4
user ?= thiagoalmeidasa@gmail.com

project:
		gcloud projects create $(project_id)
		sed -i 's/PROJECT_ID/$(project_id)/g' jhub-config.yaml notebook/worker-template.yaml

cluster:
	gcloud container clusters create $(cluster_name) \
	    --num-nodes=$(num_nodes) \
	    --machine-type=$(machine_type) \
	    --zone=$(zone) \
	    --enable-autorepair \
	    --enable-autoscaling --min-nodes=1 --max-nodes=300
	gcloud beta container node-pools create dask-scipy-preemptible \
	    --cluster=$(cluster_name) \
	    --preemptible \
	    --machine-type=$(machine_type) \
	    --zone=$(zone) \
	    --enable-autorepair \
	    --enable-autoscaling --min-nodes=1 --max-nodes=300 \
	    --node-taints preemptible=true:NoSchedule
	gcloud container clusters get-credentials $(cluster_name) --zone $(zone)

helm:
	kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(user)
	kubectl --namespace kube-system create sa tiller
	kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
	helm init --service-account tiller
	kubectl --namespace=kube-system patch deployment tiller-deploy --type=json --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["/tiller", "--listen=localhost:44134"]}]'

jupyterhub:
	helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
	helm repo update
	@echo "Installing jupyterhub..."
	@helm install jupyterhub/jupyterhub \
		--version=$(jhub_version) \
		--name=$(name) \
		--namespace=$(name) \
		-f $(config) \
		-f secret-config.yaml

upgrade:
	@echo "Upgrading..."
	@helm upgrade $(name) jupyterhub/jupyterhub \
		--version=$(jhub_version) \
		-f $(config) \
		-f secret-config.yaml

delete-helm:
	helm delete $(name) --purge
	kubectl delete namespace $(name)

delete-cluster:
	yes | gcloud container clusters delete $(cluster_name) --zone=$(zone)

shrink:
	gcloud container clusters resize $(cluster_name) --size=3 --zone=$(zone)

scale-up:
	gcloud container clusters resize $(cluster_name) --node-pool=dask-scipy-preemptible --size=720 --zone=$(zone)
	gcloud container clusters resize $(cluster_name) --node-pool=default-pool --size=80 --zone=$(zone)

docker-%: %/Dockerfile
	gcloud container builds submit \
		--tag gcr.io/$(project_id)/dask-tutorial-$(patsubst %/,%,$(dir $<)):$$(git rev-parse HEAD |cut -c1-6) \
		--timeout=1h \
		$(patsubst %/,%,$(dir $<))
	gcloud container images add-tag \
		gcr.io/$(project_id)/dask-tutorial-$(patsubst %/,%,$(dir $<)):$$(git rev-parse HEAD |cut -c1-6) \
		gcr.io/$(project_id)/dask-tutorial-$(patsubst %/,%,$(dir $<)):latest --quiet

commit:
	echo "$$(git rev-parse HEAD)"
