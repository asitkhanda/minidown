# Releasing

Releases are **tag-driven**. Pushing to `main` never ships anything to users; pushing a tag does.

```bash
# 1. Make sure main is green and the changelog is written.
# 2. Tag it.
git tag v0.3.1
git push origin v0.3.1
```

`.github/workflows/release.yml` then runs the tests, builds a Release configuration with the
version taken from the tag, packages `Minidown.app` as a zip, publishes a GitHub Release, and
bumps the Homebrew cask.

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
**`github.com/asitkhanda/homebrew-minidown`** — an empty public repo is enough; the release
workflow creates `Casks/minidown.rb` on the first run from
[`distribution/minidown.rb.template`](../distribution/minidown.rb.template).

A personal tap is deliberate rather than submitting to `homebrew/cask`: the official repo has
notability requirements a new project will not meet, and it expects notarized apps.

### The token

The workflow needs to push to that repo. Create a fine-grained personal access token with
**Contents: Read and write** scoped to `homebrew-minidown`, and add it to *this* repo as the
secret **`HOMEBREW_TAP_TOKEN`**.

Without it the release still publishes — the tap bump step is skipped.

## What is not done yet: signing and notarization

This is the honest limitation, and it is worth understanding before telling anyone to install.

The build is **ad-hoc signed and not notarized**, because notarization requires a Developer ID
certificate from the Apple Developer Program ($99/year). The practical consequence: macOS
quarantines anything downloaded from the internet, and Gatekeeper refuses to launch a quarantined
app it cannot verify. The first launch takes an extra step — **System Settings → Privacy &
Security → Open Anyway** — and on recent macOS the older right-click-to-open shortcut no longer
works.

Homebrew does not paper over this. It solves *distribution and upgrades*, not *trust*.

Two things follow:

- Every update still needs that confirmation, which is a poor experience to ask of people
  repeatedly.
- **In-app auto-updates are blocked by the same gap.** Sparkle requires the update to carry the
  same Developer ID signature as the running app, so it cannot be added meaningfully until
  signing exists.

### When you are ready to fix it

1. Enrol in the Apple Developer Program and create a **Developer ID Application** certificate.
2. Add repository secrets: the certificate as base64 (`DEVELOPER_ID_CERT_P12`, `CERT_PASSWORD`)
   and an App Store Connect API key for notarization (`AC_API_KEY_ID`, `AC_API_ISSUER_ID`,
   `AC_API_KEY_P8`). `notarytool` uses these; `altool` is gone.
3. In `release.yml`, replace the ad-hoc `CODE_SIGN_IDENTITY="-"` with the real identity, then add
   `xcrun notarytool submit --wait` and `xcrun stapler staple` before packaging.

   Two things that bite here. **Do not sign with `--deep`** — it is deprecated and signs nested
   code with the wrong flags and entitlements; sign inside-out, frameworks and XPC services first,
   the app bundle last. And **staple the `.app` before zipping it**: the ticket is written into the
   bundle, so a zip built afterwards carries it, while a zip stapled directly does not exist as an
   operation. Switching the artifact to a DMG is worth doing at this point — a DMG is stapleable as
   a unit and avoids app translocation for people who bypass Homebrew and drag it out of the image.
4. Only then add Sparkle for in-app updates, which is a separate piece of work. It needs an EdDSA
   key pair (`generate_keys`; the private half lives in the login Keychain and is exported for CI
   with `generate_keys -x` — generate it yourself, never let a tool print one into a transcript),
   `SUFeedURL` and `SUPublicEDKey` in `Info.plist`, an appcast regenerated and published on each
   release, and each artifact signed with `sign_update --ed-key-file` so the signature reaches the
   appcast entry.

   Because this app is sandboxed, Sparkle also needs its XPC services copied into the bundle and
   the matching entitlements — the sandbox is why they exist, and an unsandboxed app skips them.
   The Homebrew cask should gain `auto_updates true` in the same change, so `brew upgrade` stops
   fighting an app that now updates itself.

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
