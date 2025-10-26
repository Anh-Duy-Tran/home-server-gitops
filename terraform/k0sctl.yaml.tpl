apiVersion: k0sctl.k0sproject.io/v1beta1
kind: Cluster
metadata:
  name: k0s-cluster
spec:
  hosts:
  - role: controller
    installFlags:
      - --kubelet-extra-args="--resolv-conf=/run/systemd/resolve/resolv.conf --node-ip=${controller_private_ip}"
    ssh:
      address: ${controller_public_ip}
      user: root
      port: 22
      keyPath: ~/.ssh/id_rsa
    privateAddress: ${controller_private_ip}
    hooks:
      apply:
        before:
          - sudo iptables-restore < /etc/iptables/iptables.rules
    files:
      - name: cloudflare-tunnel-secrets
        src: ./cloudflare-tunnel/cloudflare-tunnel-secret.yaml
        dstDir: /var/lib/k0s/manifests/cloudflare-tunnel/
        perm: 0644
      - name: minio-persistent-pv
        src: ./minio/minio-persistent-pv.yaml
        dstDir: /var/lib/k0s/manifests/storage/
        perm: 0644
      - name: velero-auto-restore
        src: ./velero/auto-restore-config.yaml
        dstDir: /var/lib/k0s/manifests/velero/
        perm: 0644
      - name: iptables-rules-restore
        src: ./iptables.rules
        dstDir: /etc/iptables/
        perm: 0644

%{ for host in worker_hosts ~}
  - role: worker 
    installFlags:
      - --kubelet-extra-args="--resolv-conf=/run/systemd/resolve/resolv.conf --node-ip=${host.private_ip}"
    ssh:
      address: ${host.public_ip}
      user: root
      port: 22
      keyPath: ~/.ssh/id_rsa
    privateAddress: ${host.private_ip}
    hooks:
      apply:
        before:
          - sudo iptables-restore < /etc/iptables/iptables.rules
    files:
      - name: iptables-rules-restore
        src: ./iptables.rules
        dstDir: /etc/iptables/
        perm: 0644

%{ endfor ~}
  k0s:
    version: null  # Uses latest stable version
    config:
      apiVersion: k0s.k0sproject.io/v1beta1
      kind: ClusterConfig
      metadata:
        name: k0s
      spec:
        api:
          address: ${controller_private_ip}
          externalAddress: ${controller_public_ip}
        network:
          provider: kuberouter
          podCIDR: 10.244.0.0/16
          serviceCIDR: 10.96.0.0/12
