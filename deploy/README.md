# Deploying Cosmos-Predict2.5 on the Kubernetes GPU node

The target server is a **single-node Kubernetes cluster** (kubeadm + CRI-O, RHEL 9,
NVIDIA GPU Operator, 8 GPUs). There is **no Docker** and the host shell has **no
direct GPU access** — GPUs are only available inside pods. So:

- build the image on the node with **podman**
- run inference as a Kubernetes **Job**

Local dev stays on Windows: edit → `git commit` → `git push`. On the node: `git pull`.

---

## One-time setup (on the node)

```bash
cd ~/cosmos-predict2.5
git pull

# 0. inspect the environment
bash deploy/server_bootstrap.sh
```

Check the output:
- `podman graphRoot` and `crio root` should both be under `/var/lib/containers/storage`.
  If they match, sideloading the image works. If not, see the bottom of this file.
- node free disk should be comfortably > 100 GB.

```bash
# 1. confirm a pod actually gets a GPU (and see which model / VRAM)
kubectl apply -f deploy/k8s/00-gpu-check.yaml
kubectl logs -f gpu-check          # expect an nvidia-smi table (L4, 24 GB, etc.)
kubectl delete -f deploy/k8s/00-gpu-check.yaml

# 2. Hugging Face token as a secret (NOT committed to git)
kubectl create secret generic hf-token --from-literal=HF_TOKEN=hf_YOUR_TOKEN

# 3. persistent volume for checkpoints + outputs
kubectl apply -f deploy/k8s/10-pvc.yaml

# 4. build the image (long: pulls CUDA base + torch, ~20-40 min, needs internet)
bash deploy/build.sh
```

---

## Run inference

```bash
kubectl apply -f deploy/k8s/20-job.yaml
kubectl get pods -w                     # wait for cosmos-infer-xxxxx to be Running
kubectl logs -f job/cosmos-infer
```

First run downloads model checkpoints to the PVC (`/data/hf`) — several minutes.
Output is written to `/data/outputs/<name>/` on the PVC.

### Get the results onto Windows

```bash
# on the node: copy from the PVC out via a short-lived pod, or from the finished pod:
kubectl cp "$(kubectl get pod -l app=cosmos-infer -o jsonpath='{.items[0].metadata.name}')":/data/outputs ./outputs
```

then from Windows PowerShell:

```powershell
scp -r user1@10.52.52.7:~/cosmos-predict2.5/outputs ./outputs
```

### Change what gets generated

Edit the `env` block in `deploy/k8s/20-job.yaml` (`INPUT`, `MODEL`), or edit
`deploy/run_infer.sh`. Then:

```bash
git pull
kubectl delete job cosmos-infer
kubectl apply -f deploy/k8s/20-job.yaml
```

You only need to re-run `deploy/build.sh` when the `Dockerfile` or Python
dependencies (`pyproject.toml` / `uv.lock`) change — not for config edits,
because `deploy/` is baked into the image on each build.

Available `MODEL` values: `2B/post-trained` (default), `2B/pre-trained`,
`2B/distilled` (text2world only), `14B/post-trained`, `14B/pre-trained`.

`INPUT` options live in `assets/base/*.json` (image2world, video2world) — each
points at an image/video + prompt in the same folder.

---

## Troubleshooting

**Job pod stuck `Pending`** — `kubectl describe pod -l app=cosmos-infer`. Usually
no free GPU (`kubectl get pods -A` to find what's holding them) or PVC not bound.

**`ErrImageNeverPull` / `ImagePullBackOff`** — CRI-O can't see the podman-built
image. Confirm `sudo crictl images | grep cosmos`. See next section.

**CUDA out of memory** — add memory-saving flags in `deploy/run_infer.sh`:
`--offload-diffusion-model --offload-text-encoder --offload-tokenizer`, or use a
smaller `MODEL`, or lower `--num-output-frames` / `--resolution`.

**`401` / gated repo from Hugging Face** — accept the licenses while logged in:
<https://huggingface.co/nvidia/Cosmos-Guardrail1> and
<https://huggingface.co/nvidia/Cosmos-Predict2.5-2B>, and check the `hf-token` secret.

### If CRI-O cannot see the image (storage roots differ)

Run a throwaway local registry on the node and pull through it:

```bash
sudo podman run -d --name registry -p 5000:5000 --restart=always docker.io/library/registry:2
podman tag localhost/cosmos-predict2.5:local localhost:5000/cosmos-predict2.5:local
podman push --tls-verify=false localhost:5000/cosmos-predict2.5:local
```

Then in `deploy/k8s/20-job.yaml` set
`image: localhost:5000/cosmos-predict2.5:local` and
`imagePullPolicy: Always`, and ensure CRI-O treats `localhost:5000` as insecure
(usually default). Re-apply the Job.
