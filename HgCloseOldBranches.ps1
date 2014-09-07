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

[System.TimeSpan]$alive = [System.TimeSpan]::FromDays(60)
[System.DateTime]$now = [System.DateTime]::Now

[System.Object]$current = & hg parent -T "{node} {branch}" | ForEach-Object {
    $result = $_ | Select-Object -Property node, name
    $parts = $_.Split(' ', 2)
    
    $result.node = $parts[0]
    $result.name = $parts[1]
    $result
  } | Select-Object

"Current branch is {0}" -f $current.name

[System.Object[]]$branches = @(& hg head -T "{date(date,'%Y%m%d%H%M%S')} {node} {branch}\n" | ForEach-Object {
    $result = $_ | Select-Object -Property date, node, name
    $parts = $_.Split(' ', 3)

    [System.DateTime]$result.date = [System.DateTime]::ParseExact($parts[0], "yyyyMMddHHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
    $result.node = $parts[1]
    $result.name = $parts[2]
    $result
  } | Where-Object { $now - $_.date -gt $alive })

[System.Array]::Reverse($branches)

if ($branches.Length -eq 0) { "No old branches were detected" } else {
  "Closing {0} old branches:" -f $branches.Length
  $branches | ForEach-Object {
      "[{0:%d} days] {1}" -f ($now - $_.date), $_.name
      & hg debugsetparent $_.node | Out-Null
      & hg branch $_.name | Out-Null
      & hg commit --close-branch -X * -m $("The branch was not used for {0:%d} days and closed automatically." -f ($now - $_.date)) | Out-Null
    }

  "Restore current branch {0}" -f $current.name
  & hg debugsetparent $current.node | Out-Null
  & hg branch $current.name | Out-Null
}
