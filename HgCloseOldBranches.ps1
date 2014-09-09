# Close old branches for Mercurial
# Copyright (C) 2014  Mikhail Pilin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

if ($PSVersionTable.PSVersion.Major -lt 3) {
  throw "PS Version $($PSVersionTable.PSVersion) is below 3.0."
}

Set-StrictMode -Version Latest
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$script:VerbosePreference = "Continue"

$encoding = "cp866"
[System.TimeSpan]$alive = [System.TimeSpan]::FromDays(60)
[System.DateTime]$now = [System.DateTime]::Now

function GetHgRoot
{
    Param([System.String]$path)

    if (Test-Path -Path "$path\.hg" -PathType Container) {
        return $path
    } else {
        $parent = Split-Path -Path "$path" -Parent
        if ($parent.Length -gt 0) {
          GetHgRoot $parent
        }
    }
}

$root = GetHgRoot (Get-Item -Path .).FullName
if (-not $(Split-Path -Path "$root" -IsAbsolute)) { throw "Failed to detect repository root directory" }

Write-Host "Repository root: " -nonewline
Write-Host -foregroundcolor darkgray $root

[System.Object]$current = & hg parent --encoding $encoding -T "{node} {branch}" | ForEach-Object {
    $result = $_ | Select-Object -Property node, name
    $parts = $_.Split(' ', 2)
    
    $result.node = $parts[0]
    $result.name = $parts[1]
    $result
  } | Select-Object

Write-Host "Current branch: " -nonewline
Write-Host -foregroundcolor gray $current.name

[System.Object[]]$branches = @(& hg head --encoding $encoding -T "{date(date,'%Y%m%d%H%M%S')} {node} {branch}\n" | ForEach-Object {
    $result = $_ | Select-Object -Property date, node, name
    $parts = $_.Split(' ', 3)

    [System.DateTime]$result.date = [System.DateTime]::ParseExact($parts[0], "yyyyMMddHHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
    $result.node = $parts[1]
    $result.name = $parts[2]
    $result
  } | Where-Object { $now - $_.date -gt $alive } | Sort-Object -property date)

function EscapeBranchName
{
  Param([System.String]$name)
  $name.Replace('"', '\"')
}

if ($branches.Length -eq 0) { Write-Host "No old branches were detected" } else {
  $hgSub = "$root\.hgsub"
  $hgSubState = "$root\.hgsubstate"

  $backupHgSub = "$hgSub.tmp"
  $backupHgSubState = "$hgSubState.tmp"

  [System.Boolean]$hasHgSub = Test-Path -Path "$hgSub" -PathType Leaf
  [System.Boolean]$hasHgSubState = Test-Path -Path "$hgSubState" -PathType Leaf

  if ($hasHgSub) {
    Write-Host "Backup: " -nonewline
    Write-Host -foregroundcolor darkgray $hgSub
    Rename-Item "$hgSub" "$backupHgSub"
  }

  if ($hasHgSubState) {
    Write-Host "Backup: " -nonewline
    Write-Host -foregroundcolor darkgray $hgSubState
    Rename-Item "$hgSubState" "$backupHgSubState"
  }

  Write-Host "Closing $($branches.Length) old branches:"

  $branches | ForEach-Object {
      Write-Host "[$([System.String]::Format("{0:%d}", $now - $_.date)) days] " -nonewline
      Write-Host -foregroundcolor gray $_.name

      & hg debugsetparent $_.node | Out-Null
      if ($LastExitCode -ne 0) { Write-Warning "Failed to set node (exit code $LastExitCode)." } else {
        & hg branch $(EscapeBranchName $_.name) | Out-Null
        if ($LastExitCode -ne 0) { Write-Warning "Failed to set branch (exit code $LastExitCode)." } else {
          & hg commit --close-branch -X * -m $("The branch was not used for {0:%d} days and closed automatically." -f ($now - $_.date)) | Out-Null
          if ($LastExitCode -ne 0) { Write-Warning "Failed to commit (exit code $LastExitCode)." }
        }
      }
    }

  if ($hasHgSubState) {
    Write-Host "Restore: " -nonewline
    Write-Host -foregroundcolor darkgray $hgSubState
    Rename-Item "$backupHgSubState" "$hgSubState"
  }

  if ($hasHgSub) {
    Write-Host "Restore: " -nonewline
    Write-Host -foregroundcolor darkgray $hgSub
    Rename-Item "$backupHgSub" "$hgSub"
  }

  Write-Host "Restore current branch: " -nonewline
  Write-Host -foregroundcolor gray $current.name

  & hg debugsetparent $current.node | Out-Null
  if ($LastExitCode -ne 0) { Write-Warning "Failed to set node (exit code $LastExitCode)." } else {
    & hg branch $(EscapeBranchName $current.name) | Out-Null
    if ($LastExitCode -ne 0) { Write-Warning "Failed to set branch (exit code $LastExitCode)." }
  }
}
