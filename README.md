# PSBlueSkyPostingTools

## BlueskyPostStandAlone.ps1

BlueskyPostStandAlone.ps1 is a standalone PowerShell GUI tool for posting to Bluesky with support for mentions, tags, and links (facets).

### Requirements
- Windows with PowerShell 7+
- PSBlueSky module (install from PSGallery)
- (Optional) Microsoft.PowerShell.SecretManagement for credential vaults

### Quick Start
1. Install the required module:
   ```powershell
   Install-Module PSBlueSky -Scope CurrentUser
   # (Optional)
   Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
   ```
2. Run the script:
   ```powershell
   .\BlueskyPostStandAlone.ps1
   ```
3. Use the GUI to:
   - Enter credentials (manually or from vault)
   - Compose your post
   - Add facets (mentions, tags, links)
   - Preview and post

See `BlueskyPostStandAlone-Help.md` for full usage instructions and troubleshooting.
