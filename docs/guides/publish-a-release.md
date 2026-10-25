# How to publish a GitHub release (Zones v0.1.0)

You start on your GitHub **Dashboard**. You finish with a public release, a `v0.1.0` tag, and a working `brew` install.

## Words you need first

| Word | Meaning |
|---|---|
| **Release** | A page on GitHub for one version. It has notes and downloadable files. |
| **Draft** | A release that only you can see. Nothing is public yet, and no tag exists yet. |
| **Tag** | A name (`v0.1.0`) fixed to one commit. Git makes it when you publish. After that, the name always points to the same code. |
| **Target** | The branch or commit that the new tag points to. For this draft, it is `integration`. |
| **Asset** | A file attached to the release. Here: `Zones-0.1.0.dmg`. |
| **Pre-release** | A label that says "not stable yet". GitHub does not show it as the latest stable version. |
| **Cask** | The Homebrew recipe in `Casks/zones.rb`. It downloads the asset from the release URL and checks its sha256. |

**Why the order is important:** the cask URL is `.../releases/download/v0.1.0/Zones-0.1.0.dmg`. That URL works only after the tag exists, and the tag exists only after you publish. So `brew install` fails until step 6 is done.

---

## Step 1 — Open the repository
1. On the Dashboard, in **Top repositories**, click **wakeupdg/zones**.

## Step 2 — Open the Releases page
1. On the right side of the repository page, find **Releases**.
2. Click **Releases** (or go to `github.com/wakeupdg/zones/releases`).
3. You see **Zones 0.1.0** with a grey **Draft** label.

## Step 3 — Open the draft for edit
1. On the **Zones 0.1.0** card, click the **pencil icon** (Edit).
   - The address shows `untagged-…`. This is normal for a draft: GitHub has not made the tag yet.

## Step 4 — Check every field (do not skip this)

| Field | Correct value | Why |
|---|---|---|
| **Choose a tag** | `v0.1.0`, with the note "Excellent! This tag will be created from the target when this release is published." | The tag does not exist yet. Publishing makes it. |
| **Target** | `integration` | The tag points to the newest `integration` commit (`f8448a0` or later), which has T55 and T56. |
| **Release title** | `Zones 0.1.0` | — |
| **Notes** | The 0.1.0 text from CHANGELOG.md | Read it one time. This text becomes public. |
| **Assets** | `Zones-0.1.0.dmg`, about 2.83 MB | This is the file that the cask downloads. |
| **Release label** | **Pre-release** (not None) | The app is not notarized, and 24 manual checks are still open. A pre-release is never shown as the latest stable version. |

**CAUTION:** Do not change **Target** after you publish. A tag must always point to the same commit. If you find a mistake later, make `v0.1.1`. Do not move `v0.1.0`.

**Note about `main`:** PR #1 (`integration` → `main`) is not merged yet. That is OK. When you merge it with a merge commit, `main` contains the same commit that the tag points to.

## Step 5 — Publish
1. At the bottom, click **Publish release** (not "Save draft").
2. GitHub now does three things:
   1. It makes the tag `v0.1.0` on the target commit.
   2. It makes the release page public.
   3. It makes the asset URL work.

**CAUTION:** This step is public and hard to undo. People can download the DMG at once. If you delete the release later, the tag and any copies that people downloaded stay.

## Step 6 — Check that it worked
1. The address now ends in `/releases/tag/v0.1.0`, not `untagged-…`.
2. The label says **Pre-release** (orange), not **Draft**.
3. In the repository, click **Tags**. You see `v0.1.0`.
4. Under **Assets**, click `Zones-0.1.0.dmg`. The download must start.

## Step 7 — Test the Homebrew download (safe version)

**CAUTION:** Do **not** run `brew install` now. It puts the ad-hoc DMG app in `/Applications` and replaces the signed test build. Then your Accessibility toggle belongs to the wrong copy again (the stale-entry case from T56).

Run these in Terminal instead. They download and check the file, but they install nothing:

```bash
brew tap wakeupdg/zones https://github.com/wakeupdg/zones
```

```bash
brew fetch --cask wakeupdg/zones/zones
```

- **Pass:** `brew fetch` prints the download and ends with no sha256 error. The cask hash (`a6e42456…`) matches the published file.
- **Fail with "SHA256 mismatch":** tell Claude. The asset and the cask differ.

## Step 8 — Tell Claude
Say "published". Claude then:
1. checks the tag and the asset with `gh`;
2. writes the result in `docs/STATUS.md` and the ledger;
3. removes the "brew works only after publish" caution from the docs, if it is still there.

---

## What you learned
- A **draft** is private and has no tag. **Publishing** makes the tag, and only then do download URLs work.
- A tag is permanent. Fix mistakes with a new version, not by moving the tag.
- **Pre-release** keeps an early build from being shown as the stable version.
- Always check that the asset's sha256 matches what the installer (here, the cask) expects.
