# BlueskyPostStandAlone.ps1
# Standalone GUI for creating and posting Bluesky posts with custom facets
# Requires: PSBlueSky module

Import-Module PSBlueSky -Force

function Get-Utf8ByteOffset {
    param(
        [string]$Text,
        [int]$CharIndex
    )
    if ($CharIndex -le 0) { return 0 }
    [System.Text.Encoding]::UTF8.GetBytes($Text.Substring(0, $CharIndex)).Length
}

function FunkyFacetLink {
    # Based on PSBlueSky (_newFacetLink in helpers.ps1)
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
                byteStart = Get-Utf8ByteOffset -Text $Message -CharIndex $m.index
                byteEnd   = Get-Utf8ByteOffset -Text $Message -CharIndex ($m.index + $m.length)
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

function Test-BskyFacetInput {
    param(
        [string]$FacetType,
        [string]$FacetText,
        [string]$PostText,
        [string]$Did,
        [string]$Tag,
        [string]$Uri
    )
    if (-not $PostText) {
        [System.Windows.MessageBox]::Show('Post text is empty. Please enter post text first.', 'Validation', 'OK', 'Warning')
        return $false
    }
    if (-not $FacetText) {
        [System.Windows.MessageBox]::Show('Facet text is empty. Please enter the text that should become a facet.', 'Validation', 'OK', 'Warning')
        return $false
    }
    if ($PostText -cnotmatch [regex]::Escape($FacetText)) {
        [System.Windows.MessageBox]::Show("Facet text '$FacetText' not found in post text.", 'Validation', 'OK', 'Warning')
        return $false
    }
    switch ($FacetType) {
        'mention' {
            if (-not $Did -or $Did -notmatch '^did:') {
                [System.Windows.MessageBox]::Show('DID is missing or invalid. It should start with "did:".', 'Validation', 'OK', 'Warning')
                return $false
            }
        }
        'link' {
            if (-not $Uri -or $Uri -notmatch '^https?://') {
                [System.Windows.MessageBox]::Show('URI is missing or invalid. It should start with http:// or https://.', 'Validation', 'OK', 'Warning')
                return $false
            }
        }
        'tag' {
            if (-not $Tag) {
                [System.Windows.MessageBox]::Show('Tag name is empty.', 'Validation', 'OK', 'Warning')
                return $false
            }
            if ($Tag -match '\s') {
                [System.Windows.MessageBox]::Show('Tag name should be a single word (no spaces).', 'Validation', 'OK', 'Warning')
                return $false
            }
        }
    }
    return $true
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
    $users = Find-BskyUser -UserName $Username
    if ($users -and $users.Count -gt 0) {
        return $users
    }
    else {
        Write-Warning "User not found."
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
        $session = Get-BskySession
    }
    # Invoke the AT Protocol API directly
    $apiUrl = "https://bsky.social/xrpc/com.atproto.repo.createRecord"
    $headers = $session.CreateHeader()
    $body = @{
        repo       = $session.Did
        collection = 'app.bsky.feed.post'
        record     = $PostObject
    } | ConvertTo-Json -Depth 7
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -ContentType 'application/json'
    if ($response -and $response.uri) {
        Write-Host "Post published successfully! URI: $($response.uri)"
    }
    else {
        Write-Warning "Failed to publish post."
    }
    return $response
}

function Open-BskyPostInBrowser {
    param(
        [string]$PostUri
    )
    Start-Process $PostUri
}

Add-Type -AssemblyName PresentationFramework

function Show-DidLookupDialog {
    param(
        [string]$Username,
        [System.Windows.Controls.TextBox]$MentionDidBox
    )
    if (-not $Username) { return }
    try {
        $users = Find-BskyUserDid -Username $Username
    }
    catch {
        [System.Windows.MessageBox]::Show("Error finding DID: $($_.Exception.Message)")
        return
    }
    if (-not $users -or $users.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No users found')
        return
    }
    $selectWindow = New-Object Windows.Window
    $selectWindow.Title = 'Select Bluesky User'
    $selectWindow.Width = 500
    $selectWindow.Height = 350
    $selectWindow.WindowStartupLocation = 'CenterScreen'
    $panel = New-Object Windows.Controls.StackPanel
    $selectWindow.Content = $panel
    $listBox = New-Object Windows.Controls.ListBox
    $listBox.Height = 120
    foreach ($u in $users) {
        $desc = "Username: $($u.username) | Name: $($u.displayName) | DID: $($u.Did)"
        $desc += "`nDescription: $($u.description)"
        $item = New-Object Windows.Controls.ListBoxItem
        $item.Content = $desc
        $item.Tag = $u
        $listBox.Items.Add($item)
    }
    $panel.Children.Add($listBox)
    $userFields = @{
        Username    = New-Object Windows.Controls.TextBox
        DisplayName = New-Object Windows.Controls.TextBox
        Description = New-Object Windows.Controls.TextBox
        Did         = New-Object Windows.Controls.TextBox
    }
    foreach ($key in $userFields.Keys) {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $key
        $panel.Children.Add($label)
        $tb = $userFields[$key]
        $tb.IsReadOnly = $true
        $tb.Margin = '0,0,0,5'
        $panel.Children.Add($tb)
    }
    $listBox.Add_SelectionChanged({
            $idx = $listBox.SelectedIndex
            if ($idx -ge 0) {
                $u = $listBox.Items[$idx].Tag
                $userFields['Username'].Text = $u.username
                $userFields['DisplayName'].Text = $u.displayName
                $userFields['Description'].Text = $u.description
                $userFields['Did'].Text = $u.Did
            }
        })
    $chooseBtn = New-Object Windows.Controls.Button
    $chooseBtn.Content = 'Choose User'
    $chooseBtn.Margin = '0,10,0,0'
    $panel.Children.Add($chooseBtn)
    $chooseBtn.Add_Click({
            $idx = $listBox.SelectedIndex
            if ($idx -ge 0) {
                $u = $listBox.Items[$idx].Tag
                $MentionDidBox.Text = $u.Did
                $selectWindow.DialogResult = $true
                $selectWindow.Close()
                [System.Windows.MessageBox]::Show("DID set: $($u.Did)")
            }
            else {
                [System.Windows.MessageBox]::Show('Please select a user.')
            }
        })
    $selectWindow.ShowDialog() | Out-Null
}

function Show-BskyPostGui {
    # --- ViewModel: all mutable state scoped to this invocation ---
    $script:vm = @{
        Facets            = [System.Collections.ArrayList]::new()
        EditingFacetIndex = -1
        Credentials       = $null
    }

    # --- XAML UI Layout ---
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Bluesky Post Creator" Width="620" Height="900"
        WindowStartupLocation="CenterScreen">
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="10">
            <!-- Credentials -->
            <TextBlock Text="Enter PSBlueSky Credentials:" FontWeight="Bold" Margin="0,0,0,5"/>
            <TextBox x:Name="userBox" ToolTip="Username or handle" Margin="0,0,0,5"/>
            <PasswordBox x:Name="passBox" ToolTip="App Password" Margin="0,0,0,5"/>
            <Button x:Name="vaultBtn" Content="Get from Vault" Margin="0,0,0,10"/>

            <!-- Post text -->
            <TextBlock Text="Post Text:" FontWeight="Bold" Margin="0,10,0,5"/>
            <TextBox x:Name="postBox" Height="80" AcceptsReturn="True" TextWrapping="Wrap" Margin="0,0,0,2"/>
            <TextBlock x:Name="charCounter" Text="0 / 300" HorizontalAlignment="Right" Margin="0,0,0,10"/>

            <!-- Facets header -->
            <TextBlock Text="Facets:" FontWeight="Bold" Margin="0,10,0,5"/>

            <!-- Bluesky Username for DID lookup -->
            <TextBlock Text="Bluesky Username (for DID lookup):" Margin="0,5,0,2"/>
            <TextBox x:Name="usernameBox" Margin="0,0,0,5"/>

            <!-- Mention Facet -->
            <GroupBox Header="Mention Facet" Margin="0,5,0,5">
                <StackPanel Margin="5">
                    <TextBlock Text="Mention Text (from Post Text):"/>
                    <TextBox x:Name="mentionTextBox" Margin="0,0,0,5"/>
                    <TextBlock Text="Mention DID:"/>
                    <TextBox x:Name="mentionDidBox" Margin="0,0,0,5"/>
                    <StackPanel Orientation="Horizontal">
                        <Button x:Name="getDidBtn" Content="Get DID" Margin="0,0,10,0"/>
                        <Button x:Name="addMentionBtn" Content="Add Mention Facet"/>
                    </StackPanel>
                </StackPanel>
            </GroupBox>

            <!-- Tag Facet -->
            <GroupBox Header="Tag Facet" Margin="0,5,0,5">
                <StackPanel Margin="5">
                    <TextBlock Text="Tag Text (from Post Text):"/>
                    <TextBox x:Name="tagTextBox" Margin="0,0,0,5"/>
                    <TextBlock Text="Tag Name (one word):"/>
                    <TextBox x:Name="tagNameBox" Margin="0,0,0,5"/>
                    <Button x:Name="addTagBtn" Content="Add Tag Facet"/>
                </StackPanel>
            </GroupBox>

            <!-- Link Facet -->
            <GroupBox Header="Link Facet" Margin="0,5,0,5">
                <StackPanel Margin="5">
                    <TextBlock Text="Link Text (from Post Text):"/>
                    <TextBox x:Name="linkTextBox" Margin="0,0,0,5"/>
                    <TextBlock Text="Link URI:"/>
                    <TextBox x:Name="linkUriBox" Margin="0,0,0,5"/>
                    <Button x:Name="addLinkBtn" Content="Add Link Facet"/>
                </StackPanel>
            </GroupBox>

            <!-- Facets list -->
            <TextBlock Text="Facets Added:" FontWeight="Bold" Margin="0,10,0,5"/>
            <ListBox x:Name="addedFacetsList" Height="120" Margin="0,0,0,5"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Button x:Name="removeFacetBtn" Content="Remove Selected Facet" Margin="0,0,10,0"/>
                <Button x:Name="editFacetBtn" Content="Edit Selected Facet" Margin="0,0,10,0"/>
                <Button x:Name="cancelEditBtn" Content="Cancel Edit" Visibility="Collapsed"/>
            </StackPanel>

            <!-- Preview -->
            <TextBlock Text="Preview:" FontWeight="Bold" Margin="0,10,0,5"/>
            <TextBox x:Name="previewBox" Height="100" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,0,0,10"/>

            <!-- Action buttons -->
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Button x:Name="previewBtn" Content="Preview" Margin="0,0,10,0"/>
                <Button x:Name="postBtn" Content="Post" IsEnabled="False"/>
            </StackPanel>
        </StackPanel>
    </ScrollViewer>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # --- Resolve named controls ---
    $userBox = $window.FindName('userBox')
    $passBox = $window.FindName('passBox')
    $vaultBtn = $window.FindName('vaultBtn')
    $postBox = $window.FindName('postBox')
    $charCounter = $window.FindName('charCounter')
    $usernameBox = $window.FindName('usernameBox')
    $mentionTextBox = $window.FindName('mentionTextBox')
    $mentionDidBox = $window.FindName('mentionDidBox')
    $getDidBtn = $window.FindName('getDidBtn')
    $addMentionBtn = $window.FindName('addMentionBtn')
    $tagTextBox = $window.FindName('tagTextBox')
    $tagNameBox = $window.FindName('tagNameBox')
    $addTagBtn = $window.FindName('addTagBtn')
    $linkTextBox = $window.FindName('linkTextBox')
    $linkUriBox = $window.FindName('linkUriBox')
    $addLinkBtn = $window.FindName('addLinkBtn')
    $addedFacetsList = $window.FindName('addedFacetsList')
    $removeFacetBtn = $window.FindName('removeFacetBtn')
    $editFacetBtn = $window.FindName('editFacetBtn')
    $cancelEditBtn = $window.FindName('cancelEditBtn')
    $previewBox = $window.FindName('previewBox')
    $previewBtn = $window.FindName('previewBtn')
    $postBtn = $window.FindName('postBtn')

    # --- Shared helpers ---

    # Refresh the facet ListBox from ViewModel
    $RefreshFacetList = {
        $addedFacetsList.Items.Clear()
        $i = 0
        foreach ($f in $script:vm.Facets) {
            $type = $f.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
            $desc = "[$i] $($type): "
            switch ($type) {
                'mention' { $desc += $f.features[0].did }
                'tag' { $desc += $f.features[0].tag }
                'link' { $desc += $f.features[0].uri }
            }
            $desc += " (Bytes: $($f.index.byteStart)-$($f.index.byteEnd))"
            $addedFacetsList.Items.Add($desc)
            $i++
        }
    }

    # Reset all facet input fields and exit edit mode
    $ResetFacetInputs = {
        $usernameBox.Text = ''
        $mentionTextBox.Text = ''
        $mentionDidBox.Text = ''
        $tagTextBox.Text = ''
        $tagNameBox.Text = ''
        $linkTextBox.Text = ''
        $linkUriBox.Text = ''
        $script:vm.EditingFacetIndex = -1
        $addMentionBtn.Content = 'Add Mention Facet'
        $addTagBtn.Content = 'Add Tag Facet'
        $addLinkBtn.Content = 'Add Link Facet'
        $cancelEditBtn.Visibility = 'Collapsed'
    }

    # Populate facet input fields for a given type and clear others
    $SetFacetInputFields = {
        param([string]$Type, [string]$FacetText, $Facet)
        & $ResetFacetInputs
        switch ($Type) {
            'mention' {
                $mentionTextBox.Text = $FacetText
                $mentionDidBox.Text = $Facet.features[0].did
            }
            'tag' {
                $tagTextBox.Text = $FacetText
                $tagNameBox.Text = $Facet.features[0].tag
            }
            'link' {
                $linkTextBox.Text = $FacetText
                $linkUriBox.Text = $Facet.features[0].uri
            }
        }
    }

    # Unified add-or-edit facet handler
    $AddOrEditFacet = {
        param([string]$FacetType, [string]$FacetText, [string]$Did, [string]$Tag, [string]$Uri)
        $valid = Test-BskyFacetInput -FacetType $FacetType -FacetText $FacetText -PostText $postBox.Text -Did $Did -Tag $Tag -Uri $Uri
        if (-not $valid) { return }

        $facet = New-BskyFacet -Type $FacetType -Text $FacetText -Message $postBox.Text -Did $Did -Tag $Tag -Uri $Uri
        if (-not $facet) {
            [System.Windows.MessageBox]::Show("Facet text '$FacetText' not found in post text.", 'Error', 'OK', 'Error')
            return
        }

        if ($script:vm.EditingFacetIndex -ge 0) {
            $script:vm.Facets[$script:vm.EditingFacetIndex] = $facet
        }
        else {
            $script:vm.Facets.Add($facet) | Out-Null
        }
        & $RefreshFacetList
        & $ResetFacetInputs
        $addedFacetsList.SelectedIndex = -1
    }

    # Convert UTF-8 byte offset back to char index for display (inverse of Get-Utf8ByteOffset)
    $GetCharIndexFromByteOffset = {
        param([string]$Text, [int]$ByteOffset)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        if ($ByteOffset -ge $bytes.Length) { return $Text.Length }
        [System.Text.Encoding]::UTF8.GetString($bytes, 0, $ByteOffset).Length
    }

    # Update character counter and Post button state
    $UpdateCharCounter = {
        $len = $postBox.Text.Length
        $charCounter.Text = "$len / 300"
        if ($len -gt 300) {
            $charCounter.Foreground = [System.Windows.Media.Brushes]::Red
            $postBtn.IsEnabled = $false
        }
        elseif ($len -gt 0) {
            $charCounter.Foreground = [System.Windows.Media.Brushes]::Black
            $postBtn.IsEnabled = $true
        }
        else {
            $charCounter.Foreground = [System.Windows.Media.Brushes]::Black
            $postBtn.IsEnabled = $false
        }
    }

    # --- Event wiring ---

    # Credentials: Vault
    $vaultBtn.Add_Click({
            $secretName = Read-Host -Prompt 'Enter the Secret Name (e.g., BlueSky)'
            try {
                $cred = Get-Secret -Name $secretName -Verbose
            }
            catch {
                [System.Windows.MessageBox]::Show('Could not retrieve secret from vault.')
                return
            }
            if ($cred -and $cred -is [System.Management.Automation.PSCredential]) {
                $userBox.Text = $cred.UserName
                $passBox.Password = $cred.GetNetworkCredential().Password
                $script:vm.Credentials = $cred
                [System.Windows.MessageBox]::Show('Credentials loaded from vault.')
            }
            else {
                [System.Windows.MessageBox]::Show('Vault did not return a valid credential. Ensure the secret is a PSCredential object.')
            }
        })

    # Credentials: Manual entry on focus lost
    $syncCreds = {
        if ($userBox.Text -and $passBox.Password) {
            $script:vm.Credentials = New-Object System.Management.Automation.PSCredential($userBox.Text, (ConvertTo-SecureString $passBox.Password -AsPlainText -Force))
        }
    }
    $userBox.Add_LostFocus($syncCreds)
    $passBox.Add_LostFocus($syncCreds)

    # Character counter on text change
    $postBox.Add_TextChanged({ & $UpdateCharCounter })

    # Warn if post text change breaks facets
    $postBox.Add_LostFocus({
            $brokenIndices = @()
            $i = 0
            foreach ($facet in $script:vm.Facets) {
                try {
                    $charStart = & $GetCharIndexFromByteOffset $postBox.Text $facet.index.byteStart
                    $charEnd = & $GetCharIndexFromByteOffset $postBox.Text $facet.index.byteEnd
                    $facetText = $postBox.Text.Substring($charStart, $charEnd - $charStart)
                    # Re-check that FunkyFacetLink would find the same match at the same position
                    $recheck = Get-Utf8ByteOffset -Text $postBox.Text -CharIndex (([regex]$facetText).Match($postBox.Text).Index)
                    if ($recheck -ne $facet.index.byteStart) {
                        $brokenIndices += $i
                    }
                }
                catch {
                    $brokenIndices += $i
                }
                $i++
            }
            if ($brokenIndices.Count -gt 0) {
                [System.Windows.MessageBox]::Show("Warning: Facet(s) at index $($brokenIndices -join ', ') may be broken by text changes. Please review and re-add affected facets.", 'Facet Warning', 'OK', 'Warning')
            }
        })

    # DID lookup
    $getDidBtn.Add_Click({
            Show-DidLookupDialog -Username $usernameBox.Text -MentionDidBox $mentionDidBox
        })

    # Add Mention
    $addMentionBtn.Add_Click({
            & $AddOrEditFacet 'mention' $mentionTextBox.Text $mentionDidBox.Text '' ''
        })

    # Add Tag
    $addTagBtn.Add_Click({
            & $AddOrEditFacet 'tag' $tagTextBox.Text '' $tagNameBox.Text ''
        })

    # Add Link
    $addLinkBtn.Add_Click({
            & $AddOrEditFacet 'link' $linkTextBox.Text '' '' $linkUriBox.Text
        })

    # Cancel Edit
    $cancelEditBtn.Add_Click({
            & $ResetFacetInputs
            $addedFacetsList.SelectedIndex = -1
        })

    # Remove Facet
    $removeFacetBtn.Add_Click({
            $idx = $addedFacetsList.SelectedIndex
            if ($idx -ge 0 -and $script:vm.Facets.Count -gt $idx) {
                $script:vm.Facets.RemoveAt($idx)
                & $RefreshFacetList
                $addedFacetsList.SelectedIndex = -1
                & $ResetFacetInputs
            }
        })

    # Edit Facet
    $editFacetBtn.Add_Click({
            $idx = $addedFacetsList.SelectedIndex
            if ($idx -ge 0 -and $script:vm.Facets.Count -gt $idx) {
                $facet = $script:vm.Facets[$idx]
                $type = $facet.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
                try {
                    $charStart = & $GetCharIndexFromByteOffset $postBox.Text $facet.index.byteStart
                    $charEnd = & $GetCharIndexFromByteOffset $postBox.Text $facet.index.byteEnd
                    $facetText = $postBox.Text.Substring($charStart, $charEnd - $charStart)
                }
                catch {
                    [System.Windows.MessageBox]::Show('Could not resolve facet text. The post text may have changed.', 'Error', 'OK', 'Error')
                    return
                }
                & $SetFacetInputFields $type $facetText $facet
                $script:vm.EditingFacetIndex = $idx
                switch ($type) {
                    'mention' { $addMentionBtn.Content = 'Save Changes' }
                    'tag' { $addTagBtn.Content = 'Save Changes' }
                    'link' { $addLinkBtn.Content = 'Save Changes' }
                }
                $cancelEditBtn.Visibility = 'Visible'
            }
        })

    # Facet list selection changed — show details
    $addedFacetsList.Add_SelectionChanged({
            $idx = $addedFacetsList.SelectedIndex
            if ($idx -ge 0 -and $script:vm.Facets.Count -gt $idx) {
                $facet = $script:vm.Facets[$idx]
                $type = $facet.features[0].'$type' -replace 'app.bsky.richtext.facet#', ''
                try {
                    $charStart = & $GetCharIndexFromByteOffset $postBox.Text $facet.index.byteStart
                    $charEnd = & $GetCharIndexFromByteOffset $postBox.Text $facet.index.byteEnd
                    $facetText = $postBox.Text.Substring($charStart, $charEnd - $charStart)
                }
                catch {
                    $facetText = '(could not resolve)'
                }
                & $SetFacetInputFields $type $facetText $facet
            }
        })

    # Preview
    $previewBtn.Add_Click({
            if (-not $postBox.Text) {
                [System.Windows.MessageBox]::Show('Post text is empty.', 'Validation', 'OK', 'Warning')
                return
            }
            try {
                $postObj = New-BskyPostObject -Text $postBox.Text -Facets @($script:vm.Facets)
                $previewBox.Text = Preview-BskyPost -PostObject $postObj
            }
            catch {
                [System.Windows.MessageBox]::Show("Preview error: $($_.Exception.Message)", 'Error', 'OK', 'Error')
            }
        })

    # Post
    $postBtn.Add_Click({
            if (-not $postBox.Text) {
                [System.Windows.MessageBox]::Show('Post text is empty.', 'Validation', 'OK', 'Warning')
                return
            }
            if ($postBox.Text.Length -gt 300) {
                [System.Windows.MessageBox]::Show('Post exceeds 300 character limit.', 'Validation', 'OK', 'Warning')
                return
            }
            if (-not $script:vm.Credentials) {
                if ($userBox.Text -and $passBox.Password) {
                    $script:vm.Credentials = New-Object System.Management.Automation.PSCredential($userBox.Text, (ConvertTo-SecureString $passBox.Password -AsPlainText -Force))
                }
                else {
                    [System.Windows.MessageBox]::Show('Please enter credentials before posting.', 'Validation', 'OK', 'Warning')
                    return
                }
            }
            try {
                Start-BskySession -Credential $script:vm.Credentials | Out-Null
            }
            catch {
                [System.Windows.MessageBox]::Show("Error starting session: $($_.Exception.Message)")
                return
            }
            $postObj = New-BskyPostObject -Text $postBox.Text -Facets @($script:vm.Facets)
            try {
                $result = Publish-BskyPost -PostObject $postObj -Credentials $script:vm.Credentials
                if ($result -and $result.uri) {
                    $answer = [System.Windows.MessageBox]::Show("Post sent successfully!`n`nURI: $($result.uri)`n`nOpen in browser?", 'Success', 'YesNo', 'Information')
                    if ($answer -eq 'Yes') {
                        Open-BskyPostInBrowser -PostUri $result.uri
                    }
                }
                else {
                    [System.Windows.MessageBox]::Show('Post may have been sent, but no URI was returned.', 'Warning', 'OK', 'Warning')
                }
            }
            catch {
                [System.Windows.MessageBox]::Show("Error posting: $($_.Exception.Message)")
            }
        })

    $window.ShowDialog() | Out-Null
}

Show-BskyPostGui
