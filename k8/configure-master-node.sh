#!/bin/bash -ex

export master_node=172.16.8.10
export pod_network_cidr=192.168.0.0/16

initialize_master_node ()
{
systemctl enable kubelet
kubeadm config images pull
kubeadm init --apiserver-advertise-address=$master_node --pod-network-cidr=$pod_network_cidr
}

create_join_command ()
{
export KUBECONFIG=/etc/kubernetes/admin.conf
kubeadm token create --print-join-command | tee /vagrant/join_command.sh
chmod +x /vagrant/join_command.sh

scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa_k8 /vagrant/join_command.sh node-01:/root/
scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa_k8 /vagrant/join_command.sh node-02:/root/

}

initialize_master_node

create_join_command

sleep 90
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.profile

kubectl label node node-01 node-role.kubernetes.io/worker=worker
kubectl label node node-02 node-role.kubernetes.io/worker=worker
kubectl get node


# dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF


# metrics
kubectl apply -f https://raw.githubusercontent.com/techiescamp/kubeadm-scripts/main/manifests/metrics-server.yaml


# Nginix - Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# Nginix - Service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 32000
EOF

sleep 30

kubectl -n kube-system get pods -A

kubectl get componentstatuses

