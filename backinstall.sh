kubectl apply -k "github.com/kubernetes/cloud-provider-aws//config/default?ref=v1.31.0"
kubectl -n kube-system patch ds aws-cloud-controller-manager --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args","value":[
    "--cloud-provider=aws",
    "--cluster-name=ec2k8s",
    "--configure-cloud-routes=false",
    "--leader-elect=true",
    "--v=2"
  ]}
]'
kubectl -n kube-system get pods -l k8s-app=aws-cloud-controller-manager
kubectl -n kube-system logs ds/aws-cloud-controller-manager -c aws-cloud-controller-manager --tail=100
kubectl get nodes -o wide

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm install ebs-csi aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

