# Releasing

Releases are **tag-driven**. Pushing to `main` never ships anything to users; pushing a tag does.

```bash
# 1. Make sure main is green and the changelog is written.
# 2. Tag it.
git tag v0.3.1
git push origin v0.3.1
```

`.github/workflows/release.yml` then runs the tests, builds a Release configuration with the
version taken from the tag, signs with your **Developer ID Application** certificate, notarizes
and staples the app, packages `Minidown.app` as a zip, publishes a GitHub Release, and bumps the
Homebrew cask.

## How users install and update

```bash
brew tap asitkhanda/minidown
brew install --cask minidown
```

Updating is `brew upgrade --cask minidown`, or just `brew upgrade`.

The cask's `livecheck` block points at GitHub Releases, so `brew outdated` notices a new tag
without anyone editing the cask by hand.

## One-time setup

### The tap repository

Homebrew casks live in a repo named `homebrew-<tap>`. Create
**`github.com/asitkhanda/homebrew-minidown`** if it does not exist — an empty public repo is
enough; the release workflow creates `Casks/minidown.rb` on the first run from
[`distribution/minidown.rb.template`](../distribution/minidown.rb.template).

A personal tap is deliberate rather than submitting to `homebrew/cask`: the official repo has
notability requirements a new project will not meet.

### Homebrew tap write access

The workflow needs to push to `homebrew-minidown`. Prefer a **write-only deploy key**:

```bash
ssh-keygen -t ed25519 -f homebrew-minidown-deploy -N '' -C 'minidown-release-tap'
gh repo deploy-key add homebrew-minidown-deploy.pub \
  --repo asitkhanda/homebrew-minidown \
  --title 'minidown release' \
  --allow-write
gh secret set HOMEBREW_TAP_SSH_KEY --repo asitkhanda/minidown < homebrew-minidown-deploy
rm -f homebrew-minidown-deploy homebrew-minidown-deploy.pub
```

A fine-grained personal access token with **Contents: Read and write** scoped to
`homebrew-minidown`, stored as **`HOMEBREW_TAP_TOKEN`**, still works as a fallback.

Without either secret the release still publishes — the tap bump step is skipped.

### Signing and notarization secrets

Releases require these repository secrets on `asitkhanda/minidown`:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | Base64 of the Developer ID Application `.p12` export |
| `CERT_PASSWORD` | Password used when exporting that `.p12` |
| `AC_API_KEY_P8` | Contents of the App Store Connect API `.p8` private key |
| `AC_API_KEY_ID` | Key ID (the `XXXXXXXXXX` in `AuthKey_XXXXXXXXXX.p8`) |
| `AC_API_ISSUER_ID` | Issuer UUID — **required for Team keys**, omit for Individual keys |
| `HOMEBREW_TAP_SSH_KEY` | Private half of a write-only deploy key on `homebrew-minidown` (preferred) |
| `HOMEBREW_TAP_TOKEN` | Fine-grained PAT with Contents write on `homebrew-minidown` (fallback) |

Team ID for this project is **`D253L2SX65`**. The identity string is
`Developer ID Application: Asit Khanda (D253L2SX65)`.

#### Export the certificate for CI

On the Mac that has the Developer ID identity in Keychain Access:

```bash
# Replace PATH and the export password you choose.
security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -o developer-id.p12 \
  -P 'your-export-password'

base64 -i developer-id.p12 | pbcopy   # → DEVELOPER_ID_CERT_P12
```

Or, if you already have a `.p12` (for example from an earlier export):

```bash
base64 -i /path/to/your.p12 | pbcopy
```

Then:

```bash
gh secret set DEVELOPER_ID_CERT_P12 --repo asitkhanda/minidown   # paste base64, Ctrl-D
gh secret set CERT_PASSWORD --repo asitkhanda/minidown
gh secret set AC_API_KEY_P8 --repo asitkhanda/minidown < AuthKey_XXXXXXXXXX.p8
gh secret set AC_API_KEY_ID --repo asitkhanda/minidown --body 'XXXXXXXXXX'
# Only if this is a Team API key:
gh secret set AC_API_ISSUER_ID --repo asitkhanda/minidown --body 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
# Tap write access — prefer the deploy-key steps above; or:
gh secret set HOMEBREW_TAP_TOKEN --repo asitkhanda/minidown
```

Create the App Store Connect API key under
[Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
with at least **Developer** access. `notarytool` uses these; `altool` is gone.

### What the workflow does with them

1. Imports the `.p12` into a temporary keychain on the runner.
2. Builds Release with `CODE_SIGN_STYLE=Manual` and the Developer ID identity (hardened runtime
   is already on in `project.yml`). The signature must include `--timestamp` and must **not**
   carry `get-task-allow` (so Release sets `ENABLE_TESTABILITY=NO` and
   `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` — Debug keeps those for the debugger).
3. Submits a zip of `Minidown.app` to `notarytool --wait`, fails the job if status is not
   `Accepted` (and prints Apple's rejection log), then **staples the `.app`** before packaging
   the distribution zip — the ticket lives in the bundle, so a zip built afterwards carries it.
   Do not try to staple the zip.
4. Does **not** use `codesign --deep` — nested code would get the wrong flags and entitlements;
   `xcodebuild` signs frameworks inside-out.

## Sparkle (not yet)

In-app auto-updates are a separate piece of work. Sparkle needs an EdDSA key pair
(`generate_keys`; the private half lives in the login Keychain and is exported for CI with
`generate_keys -x` — generate it yourself, never let a tool print one into a transcript),
`SUFeedURL` and `SUPublicEDKey` in `Info.plist`, an appcast regenerated and published on each
release, and each artifact signed with `sign_update --ed-key-file`.

Because this app is sandboxed, Sparkle also needs its XPC services copied into the bundle and
the matching entitlements. The Homebrew cask should gain `auto_updates true` in the same change,
so `brew upgrade` stops fighting an app that now updates itself.

A DMG is worth considering later too — it is stapleable as a unit and avoids app translocation
for people who bypass Homebrew and drag the app out of the image.

## Versioning

Both numbers come from the tag. `v0.3.1` gives `MARKETING_VERSION` `0.3.1` and
`CURRENT_PROJECT_VERSION` `301` — `major × 10000 + minor × 100 + patch`. Reproducible from the tag
alone, unlike a run number, which resets if the repo is recreated and cannot be recomputed locally.

Keep `CURRENT_PROJECT_VERSION` in `Minidown/project.yml` in step with `MARKETING_VERSION` by the
same formula. The workflow overrides it per build, so a stale value there cannot reach a release —
but a hand-built copy would carry it, and this is a trap worth avoiding by habit. Homebrew compares
the marketing version and would not care, but **Sparkle compares `CFBundleVersion`**: an update
whose `CFBundleVersion` does not increase is one Sparkle silently never offers. No error, no log
line, no failed update — it simply never appears, and the usual first guess is a broken appcast.

## Note for the App Store

Not an option here. minidown is AGPL-3.0, and the App Store's terms impose usage restrictions and
DRM that the GPL family forbids adding — the FSF considers the two incompatible, and apps have
been pulled over exactly this. Direct distribution is the path.

There is one escape hatch, worth knowing even if you never use it: the licence binds *licensees*,
not the copyright holder. As the sole author you could ship the same code to the App Store under a
separate proprietary licence while the public repo stays AGPL-3.0. That stops being available the
moment you merge a contribution from someone else without a CLA assigning copyright — so it is a
decision to make deliberately, early, rather than discover foreclosed later.
