# jb-final-project — uptime-kuma on Azure with k3s, ArgoCD & GitHub Actions

Deploys [uptime-kuma](https://github.com/louislam/uptime-kuma) to a single Azure VM using:

- **Terraform** — creates an Azure VM + network in an *existing* resource group and runs cloud-init.
- **cloud-init** — installs single-node **k3s**, installs **ArgoCD**, and registers one ArgoCD `Application`.
- **GitHub Actions** — builds the image, pushes it to **GHCR**, and `kustomize edit set image`.
- **ArgoCD (GitOps)** — watches `k8s/` (Kustomize) on `dev` and deploys every change automatically.

```
push code ──▶ GitHub Actions ──▶ ghcr.io/.../uptime-kuma:sha-xxxx
                     │
                     └─ kustomize set image in k8s/ ──▶ commit to dev
                                                              │
                                              ArgoCD sees the change
                                                              │
                                          k3s pulls image, rolls Deployment
                                                              │
                                           http://<PUBLIC_IP>/  (uptime-kuma)
```

## Prerequisites

- Azure CLI logged in: `az login`
- An **existing** resource group you may deploy into (you will pass its name).
- An SSH key pair (`ssh-keygen -t ed25519`).
- Terraform `>= 1.5`.
- Repo admin rights on GitHub (to run the workflow and make the package public).

## ⚠️ Order matters — do these steps in sequence

`terraform apply` reports success the moment the VM exists, **not** when the app is ready, and the
first ArgoCD sync needs an image that already exists in GHCR. Follow this order:

### 1. Seed the image (pre-flight CI run)

1. Push this repo to `dev` (or merge it) so the workflow exists on GitHub.
2. Run the workflow once manually: **Actions ▸ build-and-deploy ▸ Run workflow ▸ branch `dev`**.
   - It builds `ghcr.io/noops-studio/uptime-kuma:sha-<short>` and `kustomize edit set image`
     writes that real tag into `k8s/kustomization.yaml`, committed back to `dev`.
3. Make the GHCR package **public** (so k3s can pull without a secret):
   **Profile ▸ Packages ▸ uptime-kuma ▸ Package settings ▸ Change visibility ▸ Public.**
4. Verify an anonymous pull works:
   ```bash
   docker logout ghcr.io
   docker pull ghcr.io/noops-studio/uptime-kuma:sha-<short>
   ```
5. Make sure branch `dev` is **not** protected — the CI commit-back pushes to it with `GITHUB_TOKEN`,
   which cannot bypass required reviews.

### 2. Provision the infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit it
az login
terraform init
terraform apply
```

`terraform.tfvars` you must set: `subscription_id`, `resource_group_name`, `k8s_namespace`,
`ssh_public_key_path`, `admin_source_address` (your IP `/32`, never `0.0.0.0/0`), `argocd_version`.

### 3. Wait for the app to come up (apply success ≠ ready)

```bash
ssh <admin_username>@<PUBLIC_IP>      # see the ssh_command output
cloud-init status --wait              # blocks until first-boot finishes
sudo tail -f /var/log/k3s-bootstrap.log
```

When the bootstrap log prints `Bootstrap complete`, open:

- App: `http://<PUBLIC_IP>/`
- ArgoCD: `https://<PUBLIC_IP>:30443` (reachable only from your `admin_source_address`; self-signed cert)

Initial ArgoCD admin password (run on the VM):
```bash
sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```
Rotate it after first login (or set `argocd_admin_password` in tfvars to have bootstrap set it).

## Everyday workflow (steady state)

1. Change app code under `uptime-kuma/`, push to `dev`.
2. GitHub Actions builds + pushes a new `sha-` image and commits the tag bump.
3. ArgoCD notices the changed tag (within its poll interval, ~3 min) and rolls the new image.
4. Refresh `http://<PUBLIC_IP>/`.

## Notes & limitations

- **Data is ephemeral.** uptime-kuma uses embedded SQLite at `/app/data` with no volume, so every
  roll resets monitors and re-shows the setup wizard. `replicas` stays `1` (SQLite is single-writer).
- **Plaintext HTTP** on port 80 — fine for the exam; a real deployment needs TLS.
- **k3s servicelb** binds the app's `LoadBalancer` Service to host port 80 on the VM, which Azure
  maps to the public IP. Only **one** `LoadBalancer` Service may exist; ArgoCD uses NodePort to avoid
  competing for port 80.
- `build.sh` is **superseded** by GitHub Actions and is guarded off.

