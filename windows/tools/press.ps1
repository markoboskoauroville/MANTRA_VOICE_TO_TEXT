# Presses a blob button through UI Automation (Invoke), no mouse: close, language, pause, copy, style, settings, send.
param([string]$Id = 'style')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$A = [System.Windows.Automation.AutomationElement]
$p = Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { "app not running"; exit }
$cond = New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, $p.Id)
$wins = $A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
foreach ($w in $wins) {
  $b = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, $Id)))
  if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); "pressed $Id"; exit }
}
"button $Id not found"
