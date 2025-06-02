# BlueskyPostCore.ps1
# Core logic for creating and posting Bluesky posts with custom facets
# Requires: PSBlueSky module, FunkyFacetLink function

Import-Module PSBlueSky -Force

function FunkyFacetLink {
    # this was nabbed from PSBlueSky (_newFacetLink in helpers.ps1)
    # https://docs.bsky.app/docs/advanced-guides/post-richtext
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The Bluesky message with the links')]
        [string]$Message,
        [Parameter(Mandatory, HelpMessage = 'The text of the link')]
        [string]$Text,
        [Parameter(HelpMessage = 'The URI of the link')]
        [string]$Uri,
        [Parameter(HelpMessage = 'The DID of the mention')]
        [string]$DiD,
        [Parameter(HelpMessage = 'The Tag text')]
        [string]$Tag,
        [ValidateSet('link', 'mention', 'tag')]
        [string]$FacetType = 'link'
    )

    $PSDefaultParameterValues['_verbose:block'] = 'PRIVATE'
    $feature = Switch ($FacetType) {
        'link' {
            [PSCustomObject]@{
                '$type' = 'app.bsky.richtext.facet#link'
                uri     = $Uri
            }
        }
        'mention' {
            [PSCustomObject]@{
                '$type' = 'app.bsky.richtext.facet#mention'
                did     = $DiD
            }
        }
        'tag' {
            [PSCustomObject]@{
                '$type' = 'app.bsky.richtext.facet#tag'
                tag     = $Tag
            }
        }
    }

    if ($text -match '\[|\]|\(\)') {
        $text = [regex]::Escape($text)
    }
    #the comparison test is case-sensitive
    if (([regex]$Text).IsMatch($Message)) {
        #properties of the facet object are also case-sensitive
        $m = ([regex]$Text).match($Message)
        [PSCustomObject]@{
            index    = [ordered]@{
                byteStart = $m.index
                byteEnd   = ($m.length) + ($m.index)
            }
            features = @(
                $feature
            )
        }
    }
    else {
        Write-Warning ("Text not found: $Text in $Message")
    }
}

function Get-BskyCredentials {
    param(
        [switch]$FromVault,
        [string]$VaultName = 'PowerShell',
        [string]$SecretName = 'BlueSky'
    )
    if ($FromVault) {
        if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
            try {
                return Get-Secret -Vault $VaultName -Name $SecretName
            }
            catch {
                Write-Warning "Could not retrieve secret from vault. Falling back to manual entry."
            }
        }
        else {
            Write-Warning "SecretManagement module not available. Falling back to manual entry."
        }
    }
    # Manual entry fallback
    return Get-Credential -Message "Enter your BlueSky credentials"
}

function Find-BskyUserDid {
    param(
        [string]$Username
    )
    $user = Find-BskyUser -UserName $Username | Select-Object -First 1
    if ($user -and $user.Did) {
        return $user.Did
    }
    else {
        Write-Warning "User not found or DID not available."
        return $null
    }
}

function New-BskyFacet {
    param(
        [string]$Type, # mention, tag, link
        [string]$Text,
        [string]$Message,
        [string]$Did,
        [string]$Tag,
        [string]$Uri
    )
    FunkyFacetLink -FacetType $Type -Text $Text -Message $Message -Did $Did -Tag $Tag -Uri $Uri
}

function New-BskyPostObject {
    param(
        [string]$Text,
        [array]$Facets
    )
    [ordered]@{
        '$type'     = 'app.bsky.feed.post'
        'text'      = $Text
        'createdAt' = (Get-Date -Format 'o')
        'facets'    = $Facets
    }
}

function Preview-BskyPost {
    param(
        [hashtable]$PostObject
    )
    # Simple preview (can be improved)
    $PostObject | ConvertTo-Json -Depth 7 | Out-String
}

function Publish-BskyPost {
    param(
        [hashtable]$PostObject,
        [pscredential]$Credentials
    )
    # Start session if not already started
    $session = Get-BskySession -ErrorAction SilentlyContinue
    if (-not $session) {
        Start-BskySession -Credential $Credentials | Out-Null
    }
    # Post using PSBluesky this is wrong see end of hellobskypost, invoke the API directly
    $apiUrl = "https://bsky.social/xrpc/com.atproto.repo.createRecord"
    $did = $Credentials.UserName
    $body = @{
        repo       = $did
        collection = 'app.bsky.feed.post'
        record     = $PostObject
    } | ConvertTo-Json -Depth 7
    $headers = (Get-BskySession).CreateHeader()
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -ContentType 'application/json'
    if ($response -and $response.uri) {
        Write-Host "Post published successfully! URI: $($response.uri)"
    }
    else {
        Write-Warning "Failed to publish post."
    }
    return $response
}

#    $result = New-BskyPost -Message $PostObject['text'] -Facets $PostObject['facets']
#    return $result
#}

function Open-BskyPostInBrowser {
    param(
        [string]$PostUri
    )
    Start-Process $PostUri
}

#Export-ModuleMember -Function *

# BlueskyPostGUI.ps1
# GUI for creating Bluesky posts with custom facets using BlueskyPostCore.ps1
# Requires: Import-Module ./BlueskyPostCore.ps1

#Import-Module "$PSScriptRoot/BlueskyPostCore.ps1"

Add-Type -AssemblyName PresentationFramework

function Show-BskyPostGui {
    # Main window
    $window = New-Object Windows.Window
    $window.Title = 'Bluesky Post Creator'
    $window.Width = 600
    $window.Height = 900  # Increased height for more space
    $window.WindowStartupLocation = 'CenterScreen'

    # StackPanel for layout
    $stack = New-Object Windows.Controls.StackPanel
    $window.Content = $stack

    # Credentials section
    $credLabel = New-Object Windows.Controls.TextBlock
    $credLabel.Text = 'Enter PSBlueSky Credentials:'
    $stack.Children.Add($credLabel)
    $userBox = New-Object Windows.Controls.TextBox
    $userBox.Margin = '0,0,0,5'
    $userBox.ToolTip = 'Username or handle'
    $stack.Children.Add($userBox)
    $passBox = New-Object Windows.Controls.PasswordBox
    $passBox.Margin = '0,0,0,10'
    $passBox.ToolTip = 'App Password'
    $stack.Children.Add($passBox)

    # Get from Vault button
    $vaultBtn = New-Object Windows.Controls.Button
    $vaultBtn.Content = 'Get from Vault'
    $vaultBtn.Margin = '0,0,0,10'
    $stack.Children.Add($vaultBtn)

    # Store credentials for session
    $script:bskyCreds = $null

    # Vault button event: Console-based vault/secret picker
    $vaultBtn.Add_Click({

            # Prompt for Secret Name
            $secretName = Read-Host -Prompt 'Enter the Secret Name (e.g., BlueSky)'

            # Get the secret
            try {
                $cred = $cred = Get-Secret -Name $secretName -Verbose
            }
            catch {
                [System.Windows.MessageBox]::Show('Could not retrieve secret from vault.')
                return
            }
            if ($cred -and $cred -is [System.Management.Automation.PSCredential]) {
                $userBox.Text = $cred.UserName
                $passBox.Password = $cred.GetNetworkCredential().Password
                $script:bskyCreds = $cred
                [System.Windows.MessageBox]::Show('Credentials loaded from vault.')
            }
            else {
                [System.Windows.MessageBox]::Show('Vault did not return a valid credential. Ensure the secret is a PSCredential object.')
            }
        })

    # Manual entry: update creds on focus lost
    $userBox.Add_LostFocus({
            if ($userBox.Text -and $passBox.Password) {
                $script:bskyCreds = New-Object System.Management.Automation.PSCredential($userBox.Text, (ConvertTo-SecureString $passBox.Password -AsPlainText -Force))
            }
        })
    $passBox.Add_LostFocus({
            if ($userBox.Text -and $passBox.Password) {
                $script:bskyCreds = New-Object System.Management.Automation.PSCredential($userBox.Text, (ConvertTo-SecureString $passBox.Password -AsPlainText -Force))
            }
        })

    # Post text
    $postLabel = New-Object Windows.Controls.TextBlock
    $postLabel.Text = 'Post Text:'
    $stack.Children.Add($postLabel)
    $postBox = New-Object Windows.Controls.TextBox
    $postBox.Height = 60
    $postBox.AcceptsReturn = $true
    $postBox.TextWrapping = 'Wrap'
    $postBox.Margin = '0,0,0,10'
    $stack.Children.Add($postBox)

    # Warn if changing post text breaks any facet
    $postBox.Add_LostFocus({
            $brokenFacets = @()
            $i = 0
            foreach ($facet in $global:facets) {
                $facetText = $null
                try {
                    $facetText = $postBox.Text.Substring($facet.index.byteStart, $facet.index.byteEnd - $facet.index.byteStart)
                }
                catch {}
                $type = $facet.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
                $expected = switch ($type) {
                    'mention' { $facet.features[0].did }
                    'tag' { $facet.features[0].tag }
                    'link' { $facet.features[0].uri }
                }
                # If substring fails or doesn't match original facet text, mark as broken
                if (-not $facetText -or ($type -eq 'mention' -and $facetText -ne $mentionTextBox.Text) -or ($type -eq 'tag' -and $facetText -ne $tagTextBox.Text) -or ($type -eq 'link' -and $facetText -ne $linkTextBox.Text)) {
                    $brokenFacets += $i
                }
                $i++
            }
            if ($brokenFacets.Count -gt 0) {
                [System.Windows.MessageBox]::Show("Warning: Changing the post text may have broken one or more facets. Please review and re-add any affected facets.", "Facet Warning", 'OK', 'Warning')
            }
        })

    # Facet management UI
    $facetLabel = New-Object Windows.Controls.TextBlock
    $facetLabel.Text = 'Facets:'
    $facetLabel.FontWeight = 'Bold'
    $facetLabel.Margin = '0,10,0,0'
    $stack.Children.Add($facetLabel)

    # Bluesky Username field (for DID lookup)
    $usernameLabel = New-Object Windows.Controls.TextBlock
    $usernameLabel.Text = 'Bluesky Username:'
    $usernameLabel.Margin = '0,10,0,0'
    $stack.Children.Add($usernameLabel)
    $usernameBox = New-Object Windows.Controls.TextBox
    $usernameBox.Margin = '0,0,0,5'
    $stack.Children.Add($usernameBox)

    # Mention Facet
    $mentionGroup = New-Object Windows.Controls.GroupBox
    $mentionGroup.Header = 'Mention Facet'
    $mentionPanel = New-Object Windows.Controls.StackPanel
    $mentionGroup.Content = $mentionPanel
    $mentionTextLabel = New-Object Windows.Controls.TextBlock
    $mentionTextLabel.Text = 'Mention Text (from Post Text):'
    $mentionPanel.Children.Add($mentionTextLabel)
    $mentionTextBox = New-Object Windows.Controls.TextBox
    $mentionTextBox.Margin = '0,0,0,5'
    $mentionPanel.Children.Add($mentionTextBox)
    $mentionDidLabel = New-Object Windows.Controls.TextBlock
    $mentionDidLabel.Text = 'Mention DID:'
    $mentionPanel.Children.Add($mentionDidLabel)
    $mentionDidBox = New-Object Windows.Controls.TextBox
    $mentionDidBox.Margin = '0,0,0,5'
    $mentionPanel.Children.Add($mentionDidBox)
    $getDidBtn = New-Object Windows.Controls.Button
    $getDidBtn.Content = 'Get DID'
    $getDidBtn.Margin = '0,0,0,5'
    $mentionPanel.Children.Add($getDidBtn)
    $addMentionBtn = New-Object Windows.Controls.Button
    $addMentionBtn.Content = 'Add Mention Facet'
    $mentionPanel.Children.Add($addMentionBtn)
    $stack.Children.Add($mentionGroup)

    # Mention Get DID button event
    $getDidBtn.Add_Click({
            $username = $usernameBox.Text
            if ($username) {
                try {
                    $did = Find-BskyUserDid -Username $username
                    if ($did) {
                        $mentionDidBox.Text = $did
                        [System.Windows.MessageBox]::Show("DID found: $did")
                    }
                    else {
                        [System.Windows.MessageBox]::Show('Could not find DID for that username.')
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show("Error finding DID: $($_.Exception.Message)")
                }
            }
        })

    # Tag Facet
    $tagGroup = New-Object Windows.Controls.GroupBox
    $tagGroup.Header = 'Tag Facet'
    $tagPanel = New-Object Windows.Controls.StackPanel
    $tagGroup.Content = $tagPanel
    $tagTextLabel = New-Object Windows.Controls.TextBlock
    $tagTextLabel.Text = 'Tag Text (from Post Text):'
    $tagPanel.Children.Add($tagTextLabel)
    $tagTextBox = New-Object Windows.Controls.TextBox
    $tagTextBox.Margin = '0,0,0,5'
    $tagPanel.Children.Add($tagTextBox)
    $tagNameLabel = New-Object Windows.Controls.TextBlock
    $tagNameLabel.Text = 'Tag Name (one word):'
    $tagPanel.Children.Add($tagNameLabel)
    $tagNameBox = New-Object Windows.Controls.TextBox
    $tagNameBox.Margin = '0,0,0,5'
    $tagPanel.Children.Add($tagNameBox)
    $addTagBtn = New-Object Windows.Controls.Button
    $addTagBtn.Content = 'Add Tag Facet'
    $tagPanel.Children.Add($addTagBtn)
    $stack.Children.Add($tagGroup)

    # Link Facet
    $linkGroup = New-Object Windows.Controls.GroupBox
    $linkGroup.Header = 'Link Facet'
    $linkPanel = New-Object Windows.Controls.StackPanel
    $linkGroup.Content = $linkPanel
    $linkTextLabel = New-Object Windows.Controls.TextBlock
    $linkTextLabel.Text = 'Link Text (from Post Text):'
    $linkPanel.Children.Add($linkTextLabel)
    $linkTextBox = New-Object Windows.Controls.TextBox
    $linkTextBox.Margin = '0,0,0,5'
    $linkPanel.Children.Add($linkTextBox)
    $linkUriLabel = New-Object Windows.Controls.TextBlock
    $linkUriLabel.Text = 'Link URI:'
    $linkPanel.Children.Add($linkUriLabel)
    $linkUriBox = New-Object Windows.Controls.TextBox
    $linkUriBox.Margin = '0,0,0,5'
    $linkPanel.Children.Add($linkUriBox)
    $addLinkBtn = New-Object Windows.Controls.Button
    $addLinkBtn.Content = 'Add Link Facet'
    $linkPanel.Children.Add($addLinkBtn)
    $stack.Children.Add($linkGroup)

    # Facets added display (now with ListBox for selection)
    $addedFacetsLabel = New-Object Windows.Controls.TextBlock
    $addedFacetsLabel.Text = 'Facets Added:'
    $addedFacetsLabel.FontWeight = 'Bold'
    $addedFacetsLabel.Margin = '0,10,0,0'
    $stack.Children.Add($addedFacetsLabel)
    $addedFacetsList = New-Object Windows.Controls.ListBox
    $addedFacetsList.Height = 120
    $addedFacetsList.Margin = '0,0,0,10'
    $stack.Children.Add($addedFacetsList)

    # Edit/Remove buttons
    $facetBtnPanel = New-Object Windows.Controls.StackPanel
    $facetBtnPanel.Orientation = 'Horizontal'
    $removeFacetBtn = New-Object Windows.Controls.Button
    $removeFacetBtn.Content = 'Remove Selected Facet'
    $removeFacetBtn.Margin = '0,0,10,0'
    $editFacetBtn = New-Object Windows.Controls.Button
    $editFacetBtn.Content = 'Edit Selected Facet'
    $facetBtnPanel.Children.Add($removeFacetBtn)
    $facetBtnPanel.Children.Add($editFacetBtn)
    $stack.Children.Add($facetBtnPanel)

    # Facets array for session
    $global:facets = @()
    $global:editingFacetIndex = -1  # Track which facet is being edited, -1 means not editing

    # Use a scriptblock for facet list refresh (fixes nested function issue)
    $RefreshFacetList = {
        $addedFacetsList.Items.Clear()
        $i = 0
        foreach ($f in $global:facets) {
            $type = $f.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
            $desc = "[$i] $($type): "
            switch ($type) {
                'mention' { $desc += $f.features[0].did }
                'tag' { $desc += $f.features[0].tag }
                'link' { $desc += $f.features[0].uri }
            }
            $desc += " (Text: $($f.index.byteStart)-$($f.index.byteEnd))"
            $addedFacetsList.Items.Add($desc)
            $i++
        }
    }

    # Helper: Reset all facet input fields and edit state
    $ResetFacetInputs = {
        $usernameBox.Text = ''
        $mentionTextBox.Text = ''
        $mentionDidBox.Text = ''
        $tagTextBox.Text = ''
        $tagNameBox.Text = ''
        $linkTextBox.Text = ''
        $linkUriBox.Text = ''
        $global:editingFacetIndex = -1
        $addMentionBtn.Content = 'Add Mention Facet'
        $addTagBtn.Content = 'Add Tag Facet'
        $addLinkBtn.Content = 'Add Link Facet'
        if ($CancelEditBtn) { $CancelEditBtn.Visibility = 'Collapsed' }
    }

    # Add a Cancel Edit button (hidden by default)
    $CancelEditBtn = New-Object Windows.Controls.Button
    $CancelEditBtn.Content = 'Cancel Edit'
    $CancelEditBtn.Margin = '10,0,0,0'
    $CancelEditBtn.Visibility = 'Collapsed'
    $facetBtnPanel.Children.Add($CancelEditBtn)

    $CancelEditBtn.Add_Click({
            & $ResetFacetInputs
            $addedFacetsList.SelectedIndex = -1
        })

    # Add Mention Facet event (now handles edit mode)
    $addMentionBtn.Add_Click({
            if ($global:editingFacetIndex -ge 0) {
                # Save changes to existing facet
                $facet = New-BskyFacet -Type 'mention' -Text $mentionTextBox.Text -Message $postBox.Text -Did $mentionDidBox.Text
                if ($facet) {
                    $global:facets[$global:editingFacetIndex] = $facet
                    & $RefreshFacetList
                    & $ResetFacetInputs
                    $addedFacetsList.SelectedIndex = -1
                }
                else {
                    [System.Windows.MessageBox]::Show('Mention text not found in post text. Please ensure the mention text exists in the post.')
                }
            }
            else {
                $facet = New-BskyFacet -Type 'mention' -Text $mentionTextBox.Text -Message $postBox.Text -Did $mentionDidBox.Text
                if ($facet) { $global:facets += $facet }
                & $RefreshFacetList
                # Clear mention-related fields
                $usernameBox.Text = ''
                $mentionTextBox.Text = ''
                $mentionDidBox.Text = ''
            }
        })
    # Add Tag Facet event (now handles edit mode)
    $addTagBtn.Add_Click({
            if ($global:editingFacetIndex -ge 0) {
                $facet = New-BskyFacet -Type 'tag' -Text $tagTextBox.Text -Message $postBox.Text -Tag $tagNameBox.Text
                if ($facet) {
                    $global:facets[$global:editingFacetIndex] = $facet
                    & $RefreshFacetList
                    & $ResetFacetInputs
                    $addedFacetsList.SelectedIndex = -1
                }
                else {
                    [System.Windows.MessageBox]::Show('Tag text not found in post text. Please ensure the tag text exists in the post.')
                }
            }
            else {
                $facet = New-BskyFacet -Type 'tag' -Text $tagTextBox.Text -Message $postBox.Text -Tag $tagNameBox.Text
                if ($facet) { $global:facets += $facet }
                & $RefreshFacetList
                # Clear tag-related fields
                $tagTextBox.Text = ''
                $tagNameBox.Text = ''
            }
        })
    # Add Link Facet event (now handles edit mode)
    $addLinkBtn.Add_Click({
            if ($global:editingFacetIndex -ge 0) {
                $facet = New-BskyFacet -Type 'link' -Text $linkTextBox.Text -Message $postBox.Text -Uri $linkUriBox.Text
                if ($facet) {
                    $global:facets[$global:editingFacetIndex] = $facet
                    & $RefreshFacetList
                    & $ResetFacetInputs
                    $addedFacetsList.SelectedIndex = -1
                }
                else {
                    [System.Windows.MessageBox]::Show('Link text not found in post text. Please ensure the link text exists in the post.')
                }
            }
            else {
                $facet = New-BskyFacet -Type 'link' -Text $linkTextBox.Text -Message $postBox.Text -Uri $linkUriBox.Text
                if ($facet) { $global:facets += $facet }
                & $RefreshFacetList
                # Clear link-related fields
                $linkTextBox.Text = ''
                $linkUriBox.Text = ''
            }
        })

    # Remove Facet event
    $removeFacetBtn.Add_Click({
            $idx = $addedFacetsList.SelectedIndex
            if ($idx -ge 0 -and $global:facets.Count -gt $idx) {
                $global:facets = @($global:facets | Where-Object { $_ -ne $global:facets[$idx] })
                & $RefreshFacetList
                $addedFacetsList.SelectedIndex = -1
                & $ResetFacetInputs
            }
        })

    # Edit Facet event (in-place edit)
    $editFacetBtn.Add_Click({
            $idx = $addedFacetsList.SelectedIndex
            if ($idx -ge 0 -and $global:facets.Count -gt $idx) {
                $facet = $global:facets[$idx]
                $type = $facet.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
                $facetText = $postBox.Text.Substring($facet.index.byteStart, $facet.index.byteEnd - $facet.index.byteStart)
                $global:editingFacetIndex = $idx
                switch ($type) {
                    'mention' {
                        $mentionTextBox.Text = $facetText
                        $mentionDidBox.Text = $facet.features[0].did
                        $addMentionBtn.Content = 'Save Changes'
                        $addTagBtn.Content = 'Add Tag Facet'
                        $addLinkBtn.Content = 'Add Link Facet'
                    }
                    'tag' {
                        $tagTextBox.Text = $facetText
                        $tagNameBox.Text = $facet.features[0].tag
                        $addTagBtn.Content = 'Save Changes'
                        $addMentionBtn.Content = 'Add Mention Facet'
                        $addLinkBtn.Content = 'Add Link Facet'
                    }
                    'link' {
                        $linkTextBox.Text = $facetText
                        $linkUriBox.Text = $facet.features[0].uri
                        $addLinkBtn.Content = 'Save Changes'
                        $addMentionBtn.Content = 'Add Mention Facet'
                        $addTagBtn.Content = 'Add Tag Facet'
                    }
                }
                $CancelEditBtn.Visibility = 'Visible'
            }
        })

    # When a facet is selected, show its details in the relevant input fields and clear others
    $addedFacetsList.Add_SelectionChanged({
            $idx = $addedFacetsList.SelectedIndex
            if ($idx -ge 0 -and $global:facets.Count -gt $idx) {
                $facet = $global:facets[$idx]
                $type = $facet.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
                $facetText = $postBox.Text.Substring($facet.index.byteStart, $facet.index.byteEnd - $facet.index.byteStart)
                switch ($type) {
                    'mention' {
                        $mentionTextBox.Text = $facetText
                        $mentionDidBox.Text = $facet.features[0].did
                        # Clear tag and link fields
                        $tagTextBox.Text = ''
                        $tagNameBox.Text = ''
                        $linkTextBox.Text = ''
                        $linkUriBox.Text = ''
                    }
                    'tag' {
                        $tagTextBox.Text = $facetText
                        $tagNameBox.Text = $facet.features[0].tag
                        # Clear mention and link fields
                        $mentionTextBox.Text = ''
                        $mentionDidBox.Text = ''
                        $linkTextBox.Text = ''
                        $linkUriBox.Text = ''
                    }
                    'link' {
                        $linkTextBox.Text = $facetText
                        $linkUriBox.Text = $facet.features[0].uri
                        # Clear mention and tag fields
                        $mentionTextBox.Text = ''
                        $mentionDidBox.Text = ''
                        $tagTextBox.Text = ''
                        $tagNameBox.Text = ''
                    }
                }
                # Always clear the usernameBox (Bluesky Username field)
                $usernameBox.Text = ''
            }
        })

    # Preview area
    $previewLabel = New-Object Windows.Controls.TextBlock
    $previewLabel.Text = 'Preview:'
    $stack.Children.Add($previewLabel)
    $previewBox = New-Object Windows.Controls.TextBox
    $previewBox.Height = 100
    $previewBox.IsReadOnly = $true
    $previewBox.TextWrapping = 'Wrap'
    $previewBox.Margin = '0,0,0,10'
    $stack.Children.Add($previewBox)

    # Buttons
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = 'Horizontal'
    $stack.Children.Add($btnPanel)

    $previewBtn = New-Object Windows.Controls.Button
    $previewBtn.Content = 'Preview'
    $btnPanel.Children.Add($previewBtn)
    $postBtn = New-Object Windows.Controls.Button
    $postBtn.Content = 'Post'
    $postBtn.Margin = '10,0,0,0'
    $btnPanel.Children.Add($postBtn)

    # Preview click event
    $previewBtn.Add_Click({
            $postObj = New-BskyPostObject -Text $postBox.Text -Facets $global:facets
            $previewBox.Text = Preview-BskyPost -PostObject $postObj
        })

    # Post click event
    $postBtn.Add_Click({
            if (-not $script:bskyCreds) {
                $script:bskyCreds = New-Object System.Management.Automation.PSCredential($userBox.Text, (ConvertTo-SecureString $passBox.Password -AsPlainText -Force))
            }
            try {
                # Ensure session is started before posting
                Start-BskySession -Credential $script:bskyCreds | Out-Null
            }
            catch {
                [System.Windows.MessageBox]::Show("Error starting session: $($_.Exception.Message)")
                return
            }
            $postObj = New-BskyPostObject -Text $postBox.Text -Facets $global:facets
            try {
                $result = Publish-BskyPost -PostObject $postObj -Credentials $script:bskyCreds
                [System.Windows.MessageBox]::Show('Post sent successfully!')
            }
            catch {
                [System.Windows.MessageBox]::Show("Error posting: $($_.Exception.Message)")
            }
        })

    $window.ShowDialog() | Out-Null
}

Show-BskyPostGui
