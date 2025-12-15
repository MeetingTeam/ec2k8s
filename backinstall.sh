
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm install ebs-csi aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

## instal EBS storage class