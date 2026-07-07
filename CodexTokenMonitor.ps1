param(
    [switch]$NoGuiTest,
    [switch]$GuiSmokeTest
)

$ErrorActionPreference = "Stop"

function Get-CodexTodayTokenUsage {
    $sessionRoot = Join-Path $env:USERPROFILE ".codex\sessions"
    $today = Get-Date
    $todayText = $today.ToString("yyyy-MM-dd")
    $candidateDirs = @(
        $today.AddDays(-1).ToString("yyyy\\MM\\dd"),
        $today.ToString("yyyy\\MM\\dd"),
        $today.AddDays(1).ToString("yyyy\\MM\\dd")
    ) | ForEach-Object { Join-Path $sessionRoot $_ } | Select-Object -Unique

    $result = [ordered]@{
        Date = $todayText
        Turns = 0
        InputTokens = 0L
        CachedInputTokens = 0L
        OutputTokens = 0L
        ReasoningOutputTokens = 0L
        TotalTokens = 0L
        FilesScanned = 0
        FileErrors = 0
        ParseErrors = 0
        Source = ($candidateDirs -join "; ")
    }

    $files = foreach ($dir in $candidateDirs) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -File -Filter "*.jsonl"
        }
    }

    $files | ForEach-Object {
        $result.FilesScanned += 1
        $stream = $null
        $reader = $null

        try {
            $stream = [System.IO.FileStream]::new(
                $_.FullName,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            $reader = [System.IO.StreamReader]::new($stream)

            while (($line = $reader.ReadLine()) -ne $null) {
                if (-not $line.Contains('token_count')) {
                    continue
                }

                try {
                    $event = $line | ConvertFrom-Json
                } catch {
                    $result.ParseErrors += 1
                    continue
                }

                if ($event.type -ne "event_msg" -or $event.payload.type -ne "token_count") {
                    continue
                }

                $usage = $event.payload.info.last_token_usage
                if ($null -eq $usage) {
                    continue
                }

                try {
                    $localDate = ([DateTimeOffset]::Parse($event.timestamp)).LocalDateTime.ToString("yyyy-MM-dd")
                } catch {
                    $result.ParseErrors += 1
                    continue
                }

                if ($localDate -ne $todayText) {
                    continue
                }

                $result.Turns += 1
                $result.InputTokens += [int64]$usage.input_tokens
                $result.CachedInputTokens += [int64]$usage.cached_input_tokens
                $result.OutputTokens += [int64]$usage.output_tokens
                $result.ReasoningOutputTokens += [int64]$usage.reasoning_output_tokens
                $result.TotalTokens += [int64]$usage.total_tokens
            }
        } catch {
            $result.FileErrors += 1
        } finally {
            if ($null -ne $reader) {
                $reader.Dispose()
            } elseif ($null -ne $stream) {
                $stream.Dispose()
            }
        }
    }

    [pscustomobject]$result
}

function Format-TokenCount([int64]$value) {
    return "{0:N0}" -f $value
}

if ($NoGuiTest) {
    Get-CodexTodayTokenUsage | ConvertTo-Json -Depth 4
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$darkBack = [System.Drawing.Color]::FromArgb(17, 24, 39)
$mutedText = [System.Drawing.Color]::FromArgb(209, 213, 219)
$softText = [System.Drawing.Color]::FromArgb(187, 209, 213)
$greenText = [System.Drawing.Color]::FromArgb(167, 243, 208)
$blueText = [System.Drawing.Color]::FromArgb(191, 219, 254)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Codex Token Monitor"
$form.Size = New-Object System.Drawing.Size(360, 225)
$form.MinimumSize = New-Object System.Drawing.Size(320, 56)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = $darkBack
$form.ForeColor = [System.Drawing.Color]::White
$form.Opacity = 0.85
$form.Padding = New-Object System.Windows.Forms.Padding(14)

$fontTitle = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fontSmall = New-Object System.Drawing.Font("Segoe UI", 8.5)
$fontBig = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$fontMid = New-Object System.Drawing.Font("Segoe UI", 10)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Codex Today Token"
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(14, 12)
$titleLabel.Font = $fontTitle
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Tag = "FullView"

$updatedLabel = New-Object System.Windows.Forms.Label
$updatedLabel.Text = "Waiting for refresh"
$updatedLabel.AutoSize = $true
$updatedLabel.Location = New-Object System.Drawing.Point(15, 36)
$updatedLabel.Font = $fontSmall
$updatedLabel.ForeColor = $softText
$updatedLabel.Tag = "FullView"

$compactFont = New-Object System.Drawing.Font("Segoe UI", 10)
$compactValueFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$compactTotalTextLabel = New-Object System.Windows.Forms.Label
$compactTotalTextLabel.Text = "Total "
$compactTotalTextLabel.AutoSize = $true
$compactTotalTextLabel.Location = New-Object System.Drawing.Point(14, 16)
$compactTotalTextLabel.Font = $compactFont
$compactTotalTextLabel.ForeColor = $mutedText
$compactTotalTextLabel.Visible = $false
$compactTotalTextLabel.Tag = "CompactView"

$compactTotalValueLabel = New-Object System.Windows.Forms.Label
$compactTotalValueLabel.Text = "0"
$compactTotalValueLabel.AutoSize = $true
$compactTotalValueLabel.Location = New-Object System.Drawing.Point(54, 16)
$compactTotalValueLabel.Font = $compactValueFont
$compactTotalValueLabel.ForeColor = [System.Drawing.Color]::White
$compactTotalValueLabel.Visible = $false
$compactTotalValueLabel.Tag = "CompactView"

$compactTurnsTextLabel = New-Object System.Windows.Forms.Label
$compactTurnsTextLabel.Text = " | Turns "
$compactTurnsTextLabel.AutoSize = $true
$compactTurnsTextLabel.Location = New-Object System.Drawing.Point(100, 16)
$compactTurnsTextLabel.Font = $compactFont
$compactTurnsTextLabel.ForeColor = $mutedText
$compactTurnsTextLabel.Visible = $false
$compactTurnsTextLabel.Tag = "CompactView"

$compactTurnsValueLabel = New-Object System.Windows.Forms.Label
$compactTurnsValueLabel.Text = "0"
$compactTurnsValueLabel.AutoSize = $true
$compactTurnsValueLabel.Location = New-Object System.Drawing.Point(165, 16)
$compactTurnsValueLabel.Font = $compactValueFont
$compactTurnsValueLabel.ForeColor = [System.Drawing.Color]::White
$compactTurnsValueLabel.Visible = $false
$compactTurnsValueLabel.Tag = "CompactView"

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 4000
$toolTip.InitialDelay = 450
$toolTip.ReshowDelay = 100

function New-IconButton($kind, $x, $y, $tip) {
    $button = New-Object System.Windows.Forms.Panel
    $button.Size = New-Object System.Drawing.Size(30, 28)
    $button.Location = New-Object System.Drawing.Point($x, $y)
    $button.BackColor = [System.Drawing.Color]::Transparent
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = [pscustomobject]@{
        Kind = $kind
        Hover = $false
        Down = $false
    }
    $toolTip.SetToolTip($button, $tip)

    $button.Add_MouseEnter({
        $this.Tag.Hover = $true
        $this.Invalidate()
    })
    $button.Add_MouseLeave({
        $this.Tag.Hover = $false
        $this.Tag.Down = $false
        $this.Invalidate()
    })
    $button.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $this.Tag.Down = $true
            $this.Invalidate()
        }
    })
    $button.Add_MouseUp({
        $this.Tag.Down = $false
        $this.Invalidate()
    })
    $button.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $state = $this.Tag
        $rect = New-Object System.Drawing.Rectangle(1, 1, ($this.Width - 3), ($this.Height - 3))
        $bg = [System.Drawing.Color]::FromArgb(0, 255, 255, 255)
        if (-not $this.Enabled) {
            $bg = [System.Drawing.Color]::FromArgb(18, 255, 255, 255)
        } elseif ($state.Down) {
            $bg = [System.Drawing.Color]::FromArgb(42, 255, 255, 255)
        } elseif ($state.Hover) {
            $bg = [System.Drawing.Color]::FromArgb(28, 255, 255, 255)
        }
        $brush = New-Object System.Drawing.SolidBrush($bg)
        $g.FillEllipse($brush, $rect)
        $brush.Dispose()

        $color = if ($this.Enabled) { [System.Drawing.Color]::FromArgb(230, 255, 255, 255) } else { [System.Drawing.Color]::FromArgb(105, 255, 255, 255) }
        $pen = New-Object System.Drawing.Pen($color, 1.9)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

        if ($state.Kind -eq "refresh") {
            $arcRect = New-Object System.Drawing.Rectangle(8, 7, 14, 14)
            $g.DrawArc($pen, $arcRect, 35, 285)
            $g.DrawLine($pen, 21, 8, 22, 14)
            $g.DrawLine($pen, 21, 8, 16, 8)
        } elseif ($state.Kind -eq "settings") {
            $g.DrawLine($pen, 9, 10, 21, 10)
            $g.DrawEllipse($pen, 12, 8, 4, 4)
            $g.DrawLine($pen, 9, 18, 21, 18)
            $g.DrawEllipse($pen, 16, 16, 4, 4)
        } elseif ($state.Kind -eq "compact") {
            $g.DrawLine($pen, 10, 15, 20, 15)
        } elseif ($state.Kind -eq "expand") {
            $g.DrawLine($pen, 10, 18, 15, 13)
            $g.DrawLine($pen, 15, 13, 20, 18)
        } else {
            $g.DrawLine($pen, 10, 9, 20, 19)
            $g.DrawLine($pen, 20, 9, 10, 19)
        }
        $pen.Dispose()
    })

    return $button
}

$compactButton = New-IconButton "compact" 194 12 "Compact view"
$settingsButton = New-IconButton "settings" 234 12 "Opacity settings"
$refreshButton = New-IconButton "refresh" 274 12 "Refresh now"
$closeButton = New-IconButton "close" 314 12 "Close"

function New-ValueBlock($labelText, $valueText, $x, $y, $labelColor, $big) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $labelText
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Font = $fontSmall
    $label.ForeColor = $labelColor
    $label.Tag = "FullView"

    $value = New-Object System.Windows.Forms.Label
    $value.Text = $valueText
    $value.AutoSize = $false
    $value.Size = New-Object System.Drawing.Size(145, 30)
    $value.Location = New-Object System.Drawing.Point($x, ($y + 17))
    $value.Font = $(if ($big) { $fontBig } else { $fontMid })
    $value.ForeColor = [System.Drawing.Color]::White
    $value.Tag = "FullView"

    $form.Controls.Add($label)
    $form.Controls.Add($value)
    return $value
}

$totalLabel = New-ValueBlock "Total" "0" 14 66 $greenText $true
$turnsLabel = New-ValueBlock "Turns" "0" 184 66 $blueText $true
$inputLabel = New-ValueBlock "Input" "0" 14 122 $mutedText $false
$cachedLabel = New-ValueBlock "Cached input" "0" 184 122 $mutedText $false
$outputLabel = New-ValueBlock "Output" "0" 14 170 $mutedText $false
$reasoningLabel = New-ValueBlock "Reasoning" "0" 184 170 $mutedText $false

$opacityLabel = New-Object System.Windows.Forms.Label
$opacityLabel.Text = "Background opacity"
$opacityLabel.AutoSize = $true
$opacityLabel.Location = New-Object System.Drawing.Point(14, 214)
$opacityLabel.Font = $fontSmall
$opacityLabel.ForeColor = $mutedText

$opacityValueLabel = New-Object System.Windows.Forms.Label
$opacityValueLabel.Text = "85%"
$opacityValueLabel.AutoSize = $false
$opacityValueLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$opacityValueLabel.Size = New-Object System.Drawing.Size(45, 18)
$opacityValueLabel.Location = New-Object System.Drawing.Point(301, 211)
$opacityValueLabel.Font = $fontSmall
$opacityValueLabel.ForeColor = $mutedText

$opacitySlider = New-Object System.Windows.Forms.TrackBar
$opacitySlider.Minimum = 30
$opacitySlider.Maximum = 100
$opacitySlider.TickFrequency = 10
$opacitySlider.Value = 85
$opacitySlider.Size = New-Object System.Drawing.Size(190, 30)
$opacitySlider.Location = New-Object System.Drawing.Point(110, 209)
$opacitySlider.AutoSize = $false
$opacityLabel.Visible = $false
$opacityValueLabel.Visible = $false
$opacitySlider.Visible = $false
$settingsVisible = $false
$compactMode = $false

function Move-CompactLabel($label, [int]$x) {
    $label.Location = New-Object System.Drawing.Point($x, $label.Location.Y)
    $size = [System.Windows.Forms.TextRenderer]::MeasureText($label.Text, $label.Font)
    return $x + $size.Width - 4
}

function Update-CompactSummary {
    $compactTotalValueLabel.Text = $totalLabel.Text
    $compactTurnsValueLabel.Text = $turnsLabel.Text

    $x = 14
    $x = Move-CompactLabel $compactTotalTextLabel $x
    $x = Move-CompactLabel $compactTotalValueLabel $x
    $x = Move-CompactLabel $compactTurnsTextLabel $x
    [void](Move-CompactLabel $compactTurnsValueLabel $x)
}

function Update-BackgroundOpacity {
    $form.Opacity = $opacitySlider.Value / 100.0
    $opacityValueLabel.Text = ("{0}%" -f $opacitySlider.Value)
}

function Toggle-CompactMode {
    $script:compactMode = -not $script:compactMode
    foreach ($control in $form.Controls) {
        if ($control.Tag -eq "FullView") {
            $control.Visible = -not $script:compactMode
        } elseif ($control.Tag -eq "CompactView") {
            $control.Visible = $script:compactMode
        }
    }

    if ($script:compactMode) {
        $script:settingsVisible = $false
        $opacityLabel.Visible = $false
        $opacityValueLabel.Visible = $false
        $opacitySlider.Visible = $false
        $settingsButton.Visible = $false
        $refreshButton.Visible = $true
        $compactButton.Location = New-Object System.Drawing.Point(234, 12)
        $refreshButton.Location = New-Object System.Drawing.Point(274, 12)
        $compactButton.Tag.Kind = "expand"
        $toolTip.SetToolTip($compactButton, "Expand view")
        Update-CompactSummary
        $form.Height = 58
    } else {
        $settingsButton.Visible = $true
        $refreshButton.Visible = $true
        $compactButton.Location = New-Object System.Drawing.Point(194, 12)
        $refreshButton.Location = New-Object System.Drawing.Point(274, 12)
        $compactButton.Tag.Kind = "compact"
        $toolTip.SetToolTip($compactButton, "Compact view")
        $form.Height = 225
    }
    $compactButton.Invalidate()
}

function Toggle-SettingsPanel {
    $script:settingsVisible = -not $script:settingsVisible
    $opacityLabel.Visible = $script:settingsVisible
    $opacityValueLabel.Visible = $script:settingsVisible
    $opacitySlider.Visible = $script:settingsVisible
    if ($script:settingsVisible) {
        $form.Height = 260
    } elseif (-not $script:compactMode) {
        $form.Height = 225
    }
}

function Refresh-Usage {
    try {
        $refreshButton.Enabled = $false
        $refreshButton.Invalidate()
        $updatedLabel.Text = "Refreshing..."
        [System.Windows.Forms.Application]::DoEvents()

        $usage = Get-CodexTodayTokenUsage
        $totalLabel.Text = Format-TokenCount $usage.TotalTokens
        $turnsLabel.Text = Format-TokenCount $usage.Turns
        $inputLabel.Text = Format-TokenCount $usage.InputTokens
        $cachedLabel.Text = Format-TokenCount $usage.CachedInputTokens
        $outputLabel.Text = Format-TokenCount $usage.OutputTokens
        $reasoningLabel.Text = Format-TokenCount $usage.ReasoningOutputTokens
        $updatedLabel.Text = "Updated " + (Get-Date).ToString("HH:mm:ss") + " | files " + $usage.FilesScanned
        Update-CompactSummary
    } catch {
        $updatedLabel.Text = "Refresh failed: " + $_.Exception.Message
    } finally {
        $refreshButton.Enabled = $true
        $refreshButton.Invalidate()
    }
}

$form.Controls.AddRange(@(
    $titleLabel,
    $updatedLabel,
    $compactTotalTextLabel,
    $compactTotalValueLabel,
    $compactTurnsTextLabel,
    $compactTurnsValueLabel,
    $compactButton,
    $settingsButton,
    $refreshButton,
    $closeButton,
    $opacityLabel,
    $opacityValueLabel,
    $opacitySlider
))

$dragStart = $null
$form.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragStart = $_.Location
    }
})
$form.Add_MouseMove({
    if ($null -ne $script:dragStart -and $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $form.Left += $_.X - $script:dragStart.X
        $form.Top += $_.Y - $script:dragStart.Y
    }
})
$form.Add_MouseUp({ $script:dragStart = $null })

$compactButton.Add_Click({ Toggle-CompactMode })
$settingsButton.Add_Click({ Toggle-SettingsPanel })
$refreshButton.Add_Click({ Refresh-Usage })
$closeButton.Add_Click({ $form.Close() })
$opacitySlider.Add_ValueChanged({ Update-BackgroundOpacity })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 600000
$timer.Add_Tick({ Refresh-Usage })
$timer.Start()

if ($GuiSmokeTest) {
    Toggle-CompactMode
    Toggle-CompactMode
    Toggle-SettingsPanel
    Toggle-SettingsPanel
    Write-Output ("WinForms ready: " + $form.Text)
    $timer.Stop()
    $form.Dispose()
    exit 0
}

Update-BackgroundOpacity
$form.Add_Shown({ Refresh-Usage })
[void][System.Windows.Forms.Application]::Run($form)