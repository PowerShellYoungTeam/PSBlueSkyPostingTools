# BlueskyPostStandAlone.ps1 Help Guide

BlueskyPostStandAlone.ps1 is a standalone PowerShell script for creating and posting richly formatted posts (with mentions, tags, and links) to the Bluesky social network. It provides a graphical user interface (GUI) for easy post composition and facet management.

## Prerequisites
- **Windows** with PowerShell 7+
- **PSBlueSky** PowerShell module (install from PSGallery)
- (Optional) **Microsoft.PowerShell.SecretManagement** module for credential vault integration

## Installation
1. Download `BlueskyPostStandAlone.ps1` to a folder on your computer.
2. Install the required module in PowerShell:
   ```powershell
   Install-Module PSBlueSky -Scope CurrentUser
   # (Optional, for vault support)
   Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
   ```

## Usage
1. Open PowerShell and navigate to the script's folder.
2. Run the script:
   ```powershell
   .\BlueskyPostStandAlone.ps1
   ```
3. The GUI window will appear.

### Steps in the GUI
1. **Enter Credentials**
   - Enter your Bluesky username and app password, or click "Get from Vault" to retrieve credentials from a SecretManagement vault.
2. **Compose Post**
   - Enter your post text in the "Post Text" box.
3. **Add Facets (Optional)**
   - **Mention**: Enter the mention text (must match part of your post), enter the user's DID (or use the username lookup), then click "Add Mention Facet".
   - **Tag**: Enter the tag text (from your post) and the tag name, then click "Add Tag Facet".
   - **Link**: Enter the link text (from your post) and the URL, then click "Add Link Facet".
   - Added facets appear in the list. Select a facet to edit or remove it.
4. **Preview**
   - Click "Preview" to see the JSON representation of your post.
5. **Post**
   - Click "Post" to publish to Bluesky. Success or error messages will be shown.

## Tips
- Facet text must exactly match a substring in your post text.
- Changing the post text after adding facets may break them; review warnings and re-add facets if needed.
- You can use the "Get DID" button to look up a user's DID from their Bluesky username.
- Credentials can be stored in a SecretManagement vault as a PSCredential object for convenience.

## Troubleshooting
- If you see errors about missing modules, ensure you have installed `PSBlueSky` and (optionally) `Microsoft.PowerShell.SecretManagement`.
- If posting fails, check your credentials and network connection.
- For advanced debugging, run the script from a PowerShell terminal to see additional output.

## Credits
- Built using the [PSBlueSky](https://github.com/MarshalX/PSBlueSky) module.
- GUI built with Windows Presentation Framework (WPF) via PowerShell.

---
For questions or issues, please open an issue in this repository.
