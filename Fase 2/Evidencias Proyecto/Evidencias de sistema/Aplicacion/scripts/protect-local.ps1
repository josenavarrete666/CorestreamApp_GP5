param([switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'backend'
$directory = Join-Path $backend '.local'
if (-not (Test-Path -LiteralPath $backend -PathType Container)) {
    throw 'The backend directory is missing.'
}
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    if ($Check) { throw 'The local directory is missing.' }
    [void][IO.Directory]::CreateDirectory($directory)
}
$current = [Security.Principal.WindowsIdentity]::GetCurrent().User
$allowed = @($current.Value, 'S-1-5-18', 'S-1-5-32-544')
if (-not $Check) {
    $acl = Get-Acl -LiteralPath $directory
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleAll($rule)
    }
    foreach ($sid in $allowed) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $directory -AclObject $acl
}
$acl = Get-Acl -LiteralPath $directory
if (-not $acl.AreAccessRulesProtected) { throw 'Local permissions still inherit from the project.' }
$rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
if ($rules.Count -ne $allowed.Count) { throw 'Unexpected local access rules.' }
foreach ($rule in $rules) {
    if ($rule.IdentityReference.Value -notin $allowed -or
        $rule.AccessControlType -ne 'Allow' -or
        $rule.FileSystemRights -ne 'FullControl' -or
        $rule.InheritanceFlags -ne 'ContainerInherit,ObjectInherit') {
        throw 'Unexpected local access rule.'
    }
}
'Local Windows permissions verified: current user, SYSTEM and Administrators.'
