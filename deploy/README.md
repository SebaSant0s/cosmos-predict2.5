# Deploying Cosmos-Predict2.5 on the Kubernetes GPU node

The target server is a **single-node Kubernetes cluster** (CRI-O, NVIDIA GPU
Operator) with **2 × NVIDIA L40S (48 GB each)**, 2 × Xeon Platinum 8592+
(128 cores) and 128 GB RAM. There is **no Docker** and the host shell has **no
direct GPU access** — GPUs are only available inside pods. So:

- build the image on the node with **podman**
- run inference as a Kubernetes **Job**

Local dev stays on Windows: edit → `git commit` → `git push`. On the node: `git pull`.

---

## One-time setup (on the node)

```bash
cd ~/cosmos-predict2.5
git pull

# Example inputs under assets/ are stored in Git LFS — pull the real files
# (the image copies the checkout as-is; build.sh refuses to run without them)
sudo dnf install -y git-lfs
git lfs install
git lfs pull --include='assets/base/**'

# 0. inspect the environment
bash deploy/server_bootstrap.sh
```

Check in the bootstrap output:
- **Git LFS assets: `ok`**.
- **GPU column** — this node shows `8`, model `NVIDIA-L40S-SHARED`: the GPU
  Operator time-slices the 2 physical cards into 8 shared slices. A slice gives
  a pod a whole 48 GB card, but VRAM is **not** partitioned — other pods on the
  same card share it.
- **A `local-path` storage class exists** — `deploy/k8s/10-pvc.yaml` uses it. If the
  node has a different one, change `storageClassName` there.
- **CRI-O's root is on a disk with room** — the image is ~30 GB and checkpoints
  ~100 GB+. `deploy/build.sh` auto-detects CRI-O's root and builds straight into
  it so Kubernetes can see the image (override with `CRIO_ROOT=/path`).

```bash
# 1. confirm a pod actually gets both GPUs (and see which model / VRAM)
kubectl apply -f deploy/k8s/00-gpu-check.yaml
kubectl logs -f gpu-check          # 2 different UUIDs in `nvidia-smi -L` = 2 real cards; check Memory-Usage too
kubectl delete -f deploy/k8s/00-gpu-check.yaml

# 2. Hugging Face token as a secret (NOT committed to git)
kubectl create secret generic hf-token --from-literal=HF_TOKEN=hf_YOUR_TOKEN

# 3. persistent volume for checkpoints + outputs
kubectl apply -f deploy/k8s/10-pvc.yaml

# 4. build the image (long: pulls CUDA base + torch, ~20-40 min, needs internet)
bash deploy/build.sh
```

---

## GPU time window: 19:00–03:00 Chile time

GPUs on this node are shared, so Cosmos only uses them **19:00–03:00
`America/Santiago`** (Chile's daylight-saving changes are handled automatically):

- `deploy/run_infer.sh` **refuses to start** outside the window and **stops the run
  at 03:00**. A manual `kubectl apply` during the day just fails with a message.
- Both Jobs also have `activeDeadlineSeconds: 32400` (9 h — the DST night is 9 h long) as a backstop.
- Outside the window no Cosmos pod is running, so the GPU, CPU and RAM are free.
  Disk is **not** freed: the image and checkpoints stay so the next night starts fast.
- Bypass only for a test agreed with the team: add `ENFORCE_WINDOW=0` to the Job's `env`.

## Run inference

### Manual run (inside the window)

```bash
kubectl apply -f deploy/k8s/20-job.yaml
kubectl get pods -w                     # wait for cosmos-infer-xxxxx to be Running
kubectl logs -f job/cosmos-infer
```

### Automatic nightly run

```bash
kubectl version                          # Server Version must be >= 1.27 (CronJob timeZone)
kubectl apply -f deploy/k8s/30-cronjob.yaml
kubectl get cronjob cosmos-infer-nightly # LAST SCHEDULE fills in after 19:00
kubectl get jobs                         # nightly runs: cosmos-infer-nightly-xxxxx
kubectl logs -f job/cosmos-infer-nightly-xxxxx
```

Pause it without deleting: `kubectl patch cronjob cosmos-infer-nightly -p '{"spec":{"suspend":true}}'`
(`false` to resume). Each night overwrites `/data/outputs/<name>/`, so copy out
results you want to keep.

First run downloads model checkpoints to the PVC (`/data/hf`) — several minutes.
Output is written to `/data/outputs/<name>/` on the PVC.

### Get the results onto Windows

`kubectl cp` only works on a running container, and finished inference pods
aren't, so use the small fetch pod (no GPU, fine at any hour):

```bash
kubectl apply -f deploy/k8s/40-fetch.yaml
kubectl wait --for=condition=Ready pod/cosmos-fetch
kubectl cp cosmos-fetch:/data/outputs ./outputs
kubectl delete -f deploy/k8s/40-fetch.yaml
```

then from Windows PowerShell:

```powershell
scp -r <user>@<server-ip>:~/cosmos-predict2.5/outputs ./outputs
```

### Change what gets generated

Edit the `env` block (`INPUT`, `MODEL`, `NUM_GPUS`) in `deploy/k8s/20-job.yaml`
— and in `deploy/k8s/30-cronjob.yaml` for the nightly run. Then:

```bash
git pull
kubectl delete job cosmos-infer
kubectl apply -f deploy/k8s/20-job.yaml          # or re-apply 30-cronjob.yaml
```

YAML edits need no rebuild. Re-run `deploy/build.sh` when anything **inside the
image** changes: `deploy/run_infer.sh`, `assets/`, the `Dockerfile`, or Python
dependencies (`pyproject.toml` / `uv.lock`) — the repo is copied into the image at build time.

Available `MODEL` values: `2B/post-trained` (default), `2B/pre-trained`,
`2B/distilled` (text2world only), `14B/post-trained`, `14B/pre-trained`.
With 48 GB per GPU, the 14B models are realistic on this node.

**GPUs per run:** the Job uses one GPU slice (`NUM_GPUS: "1"` and
`nvidia.com/gpu: 1`) — a full 48 GB L40S, plenty for 2B. Because the node
time-slices, asking for 2 may hand the pod the *same* card twice, and `torchrun`
would then compete with itself. Only raise both values to 2 (keep them equal) if
`gpu-check` showed two different UUIDs; `torchrun` then splits one generation
across both cards.

`INPUT` options live in `assets/base/*.json` (image2world, video2world) — each
points at an image/video + prompt in the same folder.

---

## Troubleshooting

**`outside the GPU window`** — expected before 19:00 / after 03:00 Chile time.
Delete the failed Job and apply again inside the window.

**`time zone data ... not found`** — the image was built before `tzdata` was added
to the `Dockerfile`; re-run `bash deploy/build.sh`.

**CronJob rejected: `unknown field "spec.timeZone"`** — Kubernetes is older than
1.25/1.27. Remove `timeZone:` and write the schedule in the node's own time zone.

**Job pod stuck `Pending`** — `kubectl describe pod -l app=cosmos-infer`. Usually
no free GPU slice (`kubectl get pods -A` to find what's holding them) or PVC not bound.

**`version https://git-lfs...` / JSON decode error on the input** — the assets
were LFS pointers when the image was built. Run the `git lfs pull` step, then
`bash deploy/build.sh` again.

**CUDA out of memory on a card that should be empty** — the GPUs are shared;
another pod is using VRAM on the same card. Check `nvidia-smi` in the gpu-check pod.

**`ErrImageNeverPull` / `ImagePullBackOff`** — CRI-O can't see the podman-built
image. Confirm `sudo crictl images | grep cosmos`. See next section.

**CUDA out of memory** — add memory-saving flags in `deploy/run_infer.sh`:
`--offload-diffusion-model --offload-text-encoder --offload-tokenizer`, or use a
smaller `MODEL`, or lower `--num-output-frames` / `--resolution`.

**Build fails: `flash-attn ... only has wheels with ... cp310`** — the repo pins
Python 3.13, which only works with the CUDA 13 dep set. We pin it back to 3.10
(`.python-version` and `packages/cosmos-oss/.python-version`) so the CUDA 12.8
set (`--extra=cu128`, torch 2.7) resolves. If you'd rather use CUDA 13:
set both files back to `3.13` and build with `--build-arg CUDA_NAME=cu130`
(needs NVIDIA driver 580+ on the node — check with the gpu-check pod).

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
