# SUNPOWERS - poora code (videos + images ke saath) deploy / merge karne ki ek script
# Pehle ek baar: SUNPOWERS-FULL.zip ko Downloads me rakhein (extract karne ki zarurat nahi, script khud karegi).
#
#  1) STAGING par bhejna :  powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\SUNPOWERS-DEPLOY.ps1" -Mode stage
#  2) Staging check ho jaye, SQL chala dein (Supabase -> SQL-1-SABSE-PEHLE-CHALAYEIN.sql)
#  3) PRODUCTION me merge   :  powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\SUNPOWERS-DEPLOY.ps1" -Mode prod
#  (galti ho jaye)  wapas  :  ... -Mode rollback
param(
  [ValidateSet('stage','prod','rollback')][string]$Mode = 'stage',
  [string]$Branch = 'update-oct20',        # staging branch
  [string]$ProdBranch = 'main',            # production branch (aapke live Vercel ki branch)
  [string]$Base = 'update-oct17'           # staging branch isi par se banti hai
)
$ErrorActionPreference = 'Stop'
$repo = Join-Path $env:USERPROFILE 'Downloads\sunpowers-live'
$zip  = Join-Path $env:USERPROFILE 'Downloads\SUNPOWERS-FULL.zip'
if (-not (Test-Path (Join-Path $repo '.git'))) { throw "Repo nahi mila: $repo" }
Set-Location $repo

function Need-Clean { if (git status --porcelain) { throw "Repo me pehle se badlav pade hain. Pehle 'git status' dekhein." } }

if ($Mode -eq 'stage') {
  if (-not (Test-Path $zip)) { throw "Zip nahi mila: $zip" }
  Need-Clean
  $tmp = Join-Path $env:TEMP 'sunpowers-full'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  if (-not (Test-Path (Join-Path $tmp 'crm'))) { throw "Zip ke andar crm folder nahi mila - sahi zip hai?" }
  git fetch origin
  git checkout -B $Branch "origin/$Base"
  Get-ChildItem -Path $tmp -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object { Copy-Item -Path $_.FullName -Destination $repo -Recurse -Force }
  git add -A
  git diff --cached --quiet
  if ($LASTEXITCODE -eq 0) { Write-Host 'Koi naya badlav nahi mila.' }
  else {
    $msg = @'
Rounds 30-33: Send via Link / Local Storage everywhere (link pages /d/<code>), CRM Admin logout to Admin page, Maintenance & AMC, customer flow bar + Naya Kaam + Kaam/History

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Huiy4Lhc6EjyxVBHZHxJH2
'@
    $f = Join-Path $env:TEMP 'sp-full-msg.txt'
    [System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding $false))
    git commit -F $f
    # staging branch har baar base + poori zip se dobara banti hai, isliye purani staging history ko overwrite karna sahi hai
    git push -u origin $Branch --force-with-lease
    if ($LASTEXITCODE -ne 0) { throw "Push fail hua - upar ka error dekhein. (Staging ka kuch nahi badla.)" }
    Write-Host "STAGING push ho gaya: branch $Branch. Vercel preview kuch minute me banega."
  }
  Write-Host 'Ab: staging par SQL-1-SABSE-PEHLE-CHALAYEIN.sql chalayein, sab check karein, phir -Mode prod.'
}
elseif ($Mode -eq 'prod') {
  Need-Clean
  git fetch origin
  Write-Host "Ye '$Branch' ko PRODUCTION branch '$ProdBranch' me merge karega (live site badlegi)."
  $a = Read-Host "Kya Supabase LIVE par backup + SQL-1 chal chuki hai aur staging sahi tha? Aage badhne ke liye YES likhein"
  if ($a -ne 'YES') { Write-Host 'Roka gaya. Kuch nahi badla.'; exit }
  git checkout $ProdBranch
  git pull origin $ProdBranch
  $tag = 'backup-before-' + (Get-Date -Format 'yyyyMMdd-HHmm')
  git tag $tag
  git push origin $tag
  git merge --no-ff "origin/$Branch" -m "Merge $Branch into $ProdBranch (Rounds 30-33)"
  git push origin $ProdBranch
  Write-Host "MERGE ho gaya. Vercel live deploy karega. Wapas jaana ho to: -Mode rollback  (tag: $tag)"
}
else {
  Need-Clean
  $tag = (git tag --list 'backup-before-*' --sort=-creatordate | Select-Object -First 1)
  if (-not $tag) { throw 'Koi backup tag nahi mila.' }
  $a = Read-Host "'$ProdBranch' ko tag '$tag' par wapas karna hai? YES likhein"
  if ($a -ne 'YES') { Write-Host 'Roka gaya.'; exit }
  git checkout $ProdBranch
  git reset --hard $tag
  git push --force-with-lease origin $ProdBranch
  Write-Host "Rollback ho gaya: $ProdBranch ab $tag par hai."
}
Write-Host ''
git status --short
Read-Host 'Band karne ke liye Enter dabayein'
