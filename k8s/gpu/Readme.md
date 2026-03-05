# NVIDIA GPU Setup for k3s (RTX 3060 on archbox)

This documents the steps to expose an NVIDIA GPU to Kubernetes pods on a k3s cluster where the GPU node (archbox) connects to the control plane (platform) over Tailscale.

## Prerequisites

- **archbox**: Razer Blade 14, RTX 3060 (6GB), Arch Linux, Tailscale IP `100.71.158.120`
- **platform**: k3s control plane VM, Tailscale IP `100.82.66.113`
- NVIDIA proprietary drivers installed on archbox (`nvidia-smi` works at host level)
- `nvidia-container-toolkit` installed on archbox (`sudo pacman -S nvidia-container-toolkit`)

## Key Insight

**k3s v1.34+ auto-detects the nvidia-container-toolkit** and registers the `nvidia` and `nvidia-cdi` runtimes in containerd automatically. No `config.toml.tmpl` template is needed. You can verify this after the agent is running:

```bash
sudo cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -A3 nvidia
```

## Step 1: Install k3s Server (platform)

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san 100.82.66.113 \
  --tls-san 192.168.100.10 \
  --advertise-address 100.82.66.113 \
  --write-kubeconfig-mode 644 \
  --disable traefik
```

The `--advertise-address` flag is critical — without it, the server advertises its local IP (`192.168.100.10`) which archbox can't reach over Tailscale.

Grab the join token:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

## Step 2: Join archbox as Agent

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://100.82.66.113:6443 \
  K3S_TOKEN=<token-from-step-1> \
  sh -s - agent \
  --node-name archbox \
  --node-ip 100.71.158.120
```

The `--node-ip` flag tells the agent to advertise its Tailscale IP, not the LAN IP.

Verify from platform:

```bash
kubectl get nodes
# archbox should be Ready
```

## Step 3: Set Up kubeconfig on archbox

Copy the kubeconfig from platform and update the server address:

```bash
ssh nikhil@100.82.66.113 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's|127.0.0.1|100.82.66.113|g' > ~/.kube/config
```

## Step 4: Create the RuntimeClass

This tells Kubernetes how to run pods with the `nvidia` containerd runtime:

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
```

## Step 5: Label the GPU Node

```bash
kubectl label node archbox gpu=true
```

## Step 6: Deploy the NVIDIA Device Plugin

```bash
kubectl apply -f nvidia-device-plugin.yaml
```

The device plugin daemonset must include:
- `runtimeClassName: nvidia` — so the plugin pod can see the GPU
- `nodeSelector: gpu: "true"` — so it only schedules on GPU nodes

## Step 7: Verify

Check that the GPU appears in node allocatable resources:

```bash
kubectl describe node archbox | grep -A7 Allocatable
# Should show: nvidia.com/gpu: 1
```

Test with a CUDA pod:

```bash
kubectl run gpu-test \
  --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --restart=Never \
  --overrides='{
    "spec": {
      "runtimeClassName": "nvidia",
      "nodeSelector": {"gpu": "true"},
      "containers": [{
        "name": "gpu-test",
        "image": "nvidia/cuda:12.2.0-base-ubuntu22.04",
        "command": ["nvidia-smi"],
        "resources": {"limits": {"nvidia.com/gpu": "1"}}
      }]
    }
  }'

kubectl logs gpu-test
# Should show the RTX 3060
```

Clean up:

```bash
kubectl delete pod gpu-test
```

## Troubleshooting

### Node shows NotReady after joining
Check `sudo journalctl -u k3s-agent -n 50 --no-pager`. Common causes:
- Agent can't reach the server IP (wrong Tailscale IP, firewall)
- Server advertising local IP instead of Tailscale IP (missing `--advertise-address`)

### nvidia.com/gpu not in Allocatable
- Check device plugin pod is running: `kubectl get pods -n kube-system | grep nvidia`
- Check device plugin logs: `kubectl logs -n kube-system <pod-name>`
- If logs say "Incompatible strategy detected auto" — the pod is not using the nvidia runtime. Ensure `runtimeClassName: nvidia` is set in the daemonset spec and the RuntimeClass exists.

### CNI plugin not initialized
The containerd config template is overriding k3s defaults. **Delete the template** — k3s v1.34 does not need one:

```bash
sudo rm /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
sudo systemctl restart k3s-agent
```

### Device plugin CrashLoopBackOff on platform
The daemonset is scheduling on non-GPU nodes. Add `nodeSelector: gpu: "true"` to the pod spec.
