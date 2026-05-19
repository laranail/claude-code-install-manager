# Code-signing setup

The release workflow at `.github/workflows/release.yml` supports two
paths for Authenticode-signing the launcher EXE:

1. **Azure Trusted Signing** — Microsoft's HSM-backed signing service.
   Recommended for new projects: no PFX file to store, OIDC-friendly,
   and signatures issued through this service build SmartScreen
   reputation faster than standard OV certs.
2. **PFX from a CA** (DigiCert, Sectigo, GlobalSign, SSL.com, Certum,
   etc.). The traditional approach. Simpler to wire up, but you are
   responsible for safeguarding the private key.

The workflow auto-detects which set of secrets is configured and uses
that path. If neither set is configured, the workflow falls through
to an unsigned build and `verify-release.ps1 -AllowUnsigned` keeps
CI green. Until you complete one of the setups below, every release
will be unsigned — which is exactly the state of `v0.1.0`.

Both paths produce a signed `release/dist/claude-code-install-manager.exe`
that re-execs the unsigned `.cmd` next to it. `.cmd` files cannot be
Authenticode-signed regardless of which path you pick; see the **Why a
separate `.exe`** section in `README.md` for the format-level reason.

---

## Path 1 — Azure Trusted Signing (recommended)

### Prerequisites

- An Azure subscription with billing enabled. Trusted Signing is a
  paid service (per-signature pricing, see the
  [official pricing page](https://learn.microsoft.com/azure/trusted-signing/pricing)
  for current rates).
- The Trusted Signing service available in your subscription's
  region. Check the
  [region matrix](https://learn.microsoft.com/azure/trusted-signing/concept-trusted-signing-resources-roles)
  before provisioning.
- The Azure CLI (`az`) installed locally, OR access to the Azure
  portal.

### Step 1 — Create the Trusted Signing resources

In the Azure portal:

1. Create a resource group (or reuse one), e.g. `rg-codesigning`.
2. Inside the resource group, create a **Trusted Signing Account**.
   Pick the region closest to your CI runners (`eastus` works well
   for `windows-latest`).
3. Inside the account, create a **Certificate Profile**. Pick:
   * **Profile type**: `Public Trust` for OSS releases.
   * **Identity validation**: complete the org or individual
     identity validation flow. Microsoft will email a verification
     request — this is the slowest step (1–7 business days).
4. Once identity validation completes, note three values:
   * **Trusted Signing account endpoint**, e.g.
     `https://eus.codesigning.azure.net/`.
   * **Account name**, e.g. `simtabi-codesigning`.
   * **Certificate profile name**, e.g. `simtabi-public`.

### Step 2 — Create an Entra ID app registration

The workflow signs in to Trusted Signing as a service principal.
Easiest path is a federated credential (no client secret to rotate).

```powershell
# In the same Azure tenant. Adjust display name and subscription ID.
az ad sp create-for-rbac \
    --name "claude-code-install-manager-signer" \
    --role "Trusted Signing Certificate Profile Signer" \
    --scopes "/subscriptions/<SUB_ID>/resourceGroups/rg-codesigning/providers/Microsoft.CodeSigning/codeSigningAccounts/<ACCOUNT_NAME>/certificateProfiles/<PROFILE_NAME>"
```

The command prints `appId`, `password`, and `tenant`. Save them — you
will need:

| Azure field | GitHub secret name                       |
|-------------|------------------------------------------|
| `tenant`    | `AZURE_TENANT_ID`                        |
| `appId`     | `AZURE_CLIENT_ID`                        |
| `password`  | `AZURE_CLIENT_SECRET`                    |

Alternatively, for OIDC-based federated credentials (no rotating
secret), follow Microsoft's
[GitHub-Actions federation guide](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect)
and drop `AZURE_CLIENT_SECRET` from the secret list.

### Step 3 — Wire up the six GitHub secrets

Run from your local checkout. `gh` prompts for each value
interactively:

```bash
gh secret set AZURE_TENANT_ID                     --repo simtabi/claude-code-install-manager
gh secret set AZURE_CLIENT_ID                     --repo simtabi/claude-code-install-manager
gh secret set AZURE_CLIENT_SECRET                 --repo simtabi/claude-code-install-manager
gh secret set AZURE_TRUSTED_SIGNING_ENDPOINT      --repo simtabi/claude-code-install-manager
gh secret set AZURE_TRUSTED_SIGNING_ACCOUNT       --repo simtabi/claude-code-install-manager
gh secret set AZURE_TRUSTED_SIGNING_CERT_PROFILE  --repo simtabi/claude-code-install-manager
```

`AZURE_TRUSTED_SIGNING_ENDPOINT` is the full URL including scheme,
e.g. `https://eus.codesigning.azure.net/`.

### Step 4 — Verify

Push a release candidate tag:

```bash
git tag -a v0.1.1-rc.1 -m "Trusted Signing smoke test"
git push origin v0.1.1-rc.1
```

In the workflow log, look for:

- `Detect signing mode` step output: `mode=azure`.
- `Sign with Azure Trusted Signing` step completing without error.
- `Verify signed release` step: signature `Status: Valid`, issuer is
  Microsoft's Trusted Signing CA.

Delete the RC tag after verification:

```bash
git push origin :refs/tags/v0.1.1-rc.1
git tag -d v0.1.1-rc.1
gh release delete v0.1.1-rc.1 --repo simtabi/claude-code-install-manager --yes
```

---

## Path 2 — Standard PFX from a CA

### Prerequisites

- A code-signing certificate ordered through a CA. Typical providers
  and approximate annual pricing as of 2026:
  * SSL.com — `~$179/yr` standard, `~$299/yr` EV.
  * Certum (OpenSource) — `~$80/yr` for the open-source code-signing
    cert specifically; cheapest legitimate path for a maintainer who
    only signs OSS releases. **Requires OSS project URL during validation.**
  * Sectigo — `~$229/yr` standard.
  * DigiCert — `~$474/yr` standard.
- Identity validation completed by the CA (org docs, phone callback,
  etc. — takes 1–10 business days).
- The cert exported as a `.pfx` (PKCS#12) bundle with the private key.

### Step 1 — Encode the PFX

The GitHub Actions secret store holds text only, so the binary PFX
needs to be base64-encoded once and pasted in.

**macOS / Linux:**

```bash
base64 -i path/to/codesign.pfx -o codesign.pfx.b64
```

**Windows PowerShell:**

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('path\to\codesign.pfx')) |
    Set-Content -Encoding ascii codesign.pfx.b64
```

The output file contains a single long line of base64. **Do not
commit it anywhere.** `.gitignore` already excludes `*.pfx` and
related extensions; the `.b64` file should be deleted after upload.

### Step 2 — Set the two secrets

```bash
gh secret set CODESIGN_PFX_BASE64    --repo simtabi/claude-code-install-manager < codesign.pfx.b64
gh secret set CODESIGN_PFX_PASSWORD  --repo simtabi/claude-code-install-manager
```

The second command prompts for the password.

Wipe the local base64 file:

```bash
shred -u codesign.pfx.b64 2>/dev/null || rm -f codesign.pfx.b64
```

### Step 3 — Verify

Same as for Trusted Signing, push an RC tag:

```bash
git tag -a v0.1.1-rc.1 -m "PFX signing smoke test"
git push origin v0.1.1-rc.1
```

In the workflow log:

- `Detect signing mode`: `mode=pfx`.
- `Materialize PFX from secret`: drops the file at `$RUNNER_TEMP\codesign.pfx`.
- `Build (PFX signing)`: `build.ps1` runs `signtool` and the
  `Verify signed release` step passes.

If the signature is valid but SmartScreen still warns on first run,
that is normal for a brand-new standard cert — SmartScreen reputation
builds over the first few hundred installs. EV-signed binaries skip
this warm-up.

Delete the RC tag after verification, as in Path 1.

---

## What happens if neither set of secrets is configured

The workflow's `Detect signing mode` step prints
`mode=none` and a warning, then the `Build (unsigned fallback)`
step runs `build.ps1 -SkipTests -Clean`, the
`Verify unsigned release (relaxed)` step runs
`verify-release.ps1 -AllowUnsigned`, the release archive is created
and uploaded, and the GitHub Release is published. The artifacts
work exactly the same way for users — they just see "Unknown
publisher" in the SmartScreen dialog instead of your org name.

The `release/dist/SHA256SUMS` file pins the exact hashes regardless
of signed-or-not, so users who want integrity-without-trust can
still verify with `scripts/verify-release.ps1`.

---

## Rotating credentials

- **PFX**: re-encode the new cert and overwrite `CODESIGN_PFX_BASE64` +
  `CODESIGN_PFX_PASSWORD` with `gh secret set`. The next tagged
  release picks up the new cert automatically.
- **Trusted Signing app secret**: regenerate the secret in the Azure
  portal under the app registration's *Certificates & secrets* blade
  and overwrite `AZURE_CLIENT_SECRET`. If you migrated to federated
  credentials, there is no secret to rotate.

Both paths support overlapping cert validity, so you can roll new
credentials without downtime by overwriting the secret a day or
two before the old one expires.

---

## Removing signing entirely

`gh secret delete <NAME> --repo simtabi/claude-code-install-manager`
for each of the relevant secrets, or use the GitHub web UI under
*Settings → Secrets and variables → Actions*. The workflow falls
back to the unsigned path on the next release.
