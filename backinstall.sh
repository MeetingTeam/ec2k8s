git clone https://github.com/kubernetes/cloud-provider-aws.git
cd cloud-provider-aws/examples/existing-cluster/base
kubectl create -k .
kubectl get daemonset -n kube-system
kubectl get pods -n kube-system

kubectl get nodes -o wide

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm install ebs-csi aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

