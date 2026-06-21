# `apps/` — ArgoCD watch folder (App-of-Apps)

ArgoCD watches **this folder**. Every `*.yaml` here is an ArgoCD
[`Application`](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications).
Add one, commit, push → ArgoCD deploys it. Delete one, push → ArgoCD removes it.

You **never** have to touch Terraform or SSH into the VM to deploy a new app.

## How it works

```
root-app  (Application, applied once at bootstrap)
   │  watches apps/ recursively, auto-sync
   ▼
apps/
  uptime-kuma.yaml   → Helm chart  my-monitor/   → namespace uptime-kuma
  <your-app>.yaml    → whatever YOU point it at  → namespace YOU choose
```

`root-app` is itself an ArgoCD Application whose `source.path` is `apps/` with
directory recursion turned on. When it syncs, it applies every Application file
in here. Each of those Applications then deploys its own workload. That nesting
is the **App-of-Apps** pattern.

## Deploy a new app (the drop-in workflow)

1. Copy the template:

   ```bash
   cp apps/example-app.yaml.template apps/my-new-app.yaml
   ```

2. Edit `apps/my-new-app.yaml`:
   - `metadata.name` — unique name
   - `spec.source.path` — folder in this repo (or set a different `repoURL`)
     holding your Helm chart or plain `.yaml` manifests
   - `spec.source.helm.values` — **this app's values, inline** (if it's a Helm
     chart). They override the chart's own `values.yaml`, so each app keeps its
     config in its own file here and the chart stays generic. Delete the `helm:`
     block if the path is plain manifests.
   - `spec.destination.namespace` — namespace to deploy into (auto-created)

3. Commit and push to the `dev` branch:

   ```bash
   git add apps/my-new-app.yaml
   git commit -m "feat: deploy my-new-app via ArgoCD"
   git push
   ```

ArgoCD picks it up on its next poll (default ~3 min) and deploys it. Watch it in
the ArgoCD UI, or:

```bash
kubectl -n argocd get applications
```

## Rules

- Files must be ArgoCD `Application` (or `ApplicationSet`) manifests, **not** raw
  Deployments/Services. Put raw manifests in their own folder and point an
  Application at that folder (see the template).
- `metadata.namespace` is always `argocd` (Applications live there). The app's
  *workload* namespace is `spec.destination.namespace`.
- `.template` files are ignored examples — only real `.yaml` files are deployed.
