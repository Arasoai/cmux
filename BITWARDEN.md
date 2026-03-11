# Bitwarden Credential Autofill

cmux (Araso Edition) includes built-in Bitwarden credential autofill for browser panes. When you navigate to a login page, cmux detects the form and can fill your credentials from Bitwarden.

## Setup

### 1. Install the Bitwarden CLI

```bash
brew install bitwarden-cli
```

Or download from https://bitwarden.com/help/cli/

### 2. Log in to Bitwarden

```bash
bw login
```

### 3. Unlock your vault

```bash
bw unlock
```

This prints a session token. You have three options to make it available to cmux:

**Option A: Session file (recommended)**

```bash
mkdir -p ~/.config/cmux
bw unlock --raw > ~/.config/cmux/bw-session
```

**Option B: Environment variable**

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
export BW_SESSION="<your-session-token>"
```

Then relaunch cmux.

**Option C: Unlock from cmux**

If your vault is locked, cmux will prompt for your master password when you click the key icon in the browser address bar.

## Usage

1. Open a browser pane in cmux and navigate to a login page
2. cmux auto-detects login forms (password + username fields)
3. Click the **key icon** in the browser address bar
4. If one credential matches, it fills automatically
5. If multiple match, a picker appears to choose which one

## How it works

- cmux calls the `bw` CLI to search credentials matching the current domain
- Credentials are cached per-domain (in-memory only, never written to disk)
- Master password is passed via environment variable (never in process arguments)
- Form detection uses a MutationObserver for SPAs that load forms dynamically
- Only the main frame is scanned (no cross-origin iframes)

## Troubleshooting

**Key icon doesn't appear?**
The page may not have a detectable login form. The form needs a password input and a username/email field.

**"No saved credentials found"?**
Check that the credential's URI in Bitwarden matches the domain you're visiting. Run `bw list items --url example.com` to verify.

**bw not found?**
cmux looks for `bw` at `/opt/homebrew/bin/bw`, `/usr/local/bin/bw`, `/usr/bin/bw`, or via `which bw`. Ensure it's installed and on your PATH.

**Session expired?**
Re-run `bw unlock --raw > ~/.config/cmux/bw-session` to refresh your session token.
