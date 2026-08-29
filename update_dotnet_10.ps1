#requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkingDir = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-XmlDocument {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $false

    try {
        $document.Load($Path)
    }
    catch {
        throw "Nao foi possivel ler o XML '$Path': $($_.Exception.Message)"
    }

    return $document
}

function Save-XmlDocument {
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$OmitXmlDeclaration
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = [Environment]::NewLine
    $settings.OmitXmlDeclaration = $OmitXmlDeclaration.IsPresent
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $writer = $null

    try {
        if ($OmitXmlDeclaration -and $null -ne $Document.FirstChild -and $Document.FirstChild.NodeType -eq [System.Xml.XmlNodeType]::XmlDeclaration) {
            [void]$Document.RemoveChild($Document.FirstChild)
        }

        $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
        $Document.Save($writer)
    }
    catch {
        throw "Nao foi possivel gravar o XML '$Path': $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }
}

function New-XmlElement {
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Parent,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrEmpty($Parent.NamespaceURI)) {
        return $Document.CreateElement($Name)
    }

    return $Document.CreateElement($Name, $Parent.NamespaceURI)
}

function Get-XmlElementValue {
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Element,

        [Parameter(Mandatory)]
        [string]$AttributeName
    )

    $attribute = $Element.GetAttributeNode($AttributeName)

    if ($null -ne $attribute -and -not [string]::IsNullOrWhiteSpace($attribute.Value)) {
        return $attribute.Value.Trim()
    }

    $child = $Element.SelectSingleNode("./*[local-name()='Version']")

    if ($null -ne $child -and -not [string]::IsNullOrWhiteSpace($child.InnerText)) {
        return $child.InnerText.Trim()
    }

    return $null
}

function Invoke-DotNet {
    param (
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & dotnet @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "O comando 'dotnet $($Arguments -join ' ')' falhou com codigo $LASTEXITCODE."
    }
}

function Get-GlobalDotNetToolList {
    $output = & dotnet tool list --global 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel consultar as ferramentas globais do .NET (codigo $LASTEXITCODE)."
    }

    return $output
}

function New-CentralPackageManagementDocument {
    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $false

    [void]$document.AppendChild($document.CreateXmlDeclaration('1.0', 'utf-8', $null))
    [void]$document.AppendChild($document.CreateElement('Project'))

    return $document
}

function Ensure-CentralPackageManagement {
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document
    )

    $root = $Document.DocumentElement
    $propertyGroup = $root.SelectSingleNode("./*[local-name()='PropertyGroup']")

    if ($null -eq $propertyGroup) {
        $propertyGroup = New-XmlElement -Document $Document -Parent $root -Name 'PropertyGroup'
        [void]$root.AppendChild($propertyGroup)
    }

    $centralProperty = $propertyGroup.SelectSingleNode("./*[local-name()='ManagePackageVersionsCentrally']")

    if ($null -eq $centralProperty) {
        $centralProperty = New-XmlElement -Document $Document -Parent $propertyGroup -Name 'ManagePackageVersionsCentrally'
        $centralProperty.InnerText = 'true'
        [void]$propertyGroup.AppendChild($centralProperty)
        return $true
    }

    if ($centralProperty.InnerText -ne 'true') {
        $centralProperty.InnerText = 'true'
        return $true
    }

    return $false
}

function Get-PackageItemGroup {
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document
    )

    $root = $Document.DocumentElement

    foreach ($itemGroup in @($root.SelectNodes("./*[local-name()='ItemGroup']"))) {
        if ($null -ne $itemGroup.SelectSingleNode("./*[local-name()='PackageVersion']")) {
            return $itemGroup
        }
    }

    $itemGroup = New-XmlElement -Document $Document -Parent $root -Name 'ItemGroup'
    [void]$root.AppendChild($itemGroup)

    return $itemGroup
}

function Add-MissingPackageVersions {
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, string]]$Packages
    )

    $itemGroup = Get-PackageItemGroup -Document $Document
    $changed = $false

    foreach ($packageId in @($Packages.Keys | Sort-Object)) {
        $existingPackage = $null

        foreach ($packageVersion in @($Document.SelectNodes("//*[local-name()='PackageVersion']"))) {
            if ($packageVersion.GetAttribute('Include') -ieq $packageId) {
                $existingPackage = $packageVersion
                break
            }
        }

        if ($null -eq $existingPackage) {
            $packageVersion = New-XmlElement -Document $Document -Parent $itemGroup -Name 'PackageVersion'
            $packageVersion.SetAttribute('Include', $packageId)
            $packageVersion.SetAttribute('Version', $Packages[$packageId])
            [void]$itemGroup.AppendChild($packageVersion)
            $changed = $true
        }
    }

    return $changed
}

function Update-ProjectDocument {
    param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$ProjectFile,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, string]]$Packages
    )

    $document = Read-XmlDocument -Path $ProjectFile.FullName
    $changed = $false

    if ($null -ne $document.FirstChild -and $document.FirstChild.NodeType -eq [System.Xml.XmlNodeType]::XmlDeclaration) {
        $changed = $true
    }

    foreach ($frameworkNode in @($document.SelectNodes("//*[local-name()='TargetFramework' or local-name()='TargetFrameworks']"))) {
        $updatedValue = [regex]::Replace(
            $frameworkNode.InnerText,
            '\bnet\d+(?:\.\d+)+',
            'net10.0',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($updatedValue -ne $frameworkNode.InnerText) {
            $frameworkNode.InnerText = $updatedValue
            $changed = $true
        }
    }

    foreach ($packageReference in @($document.SelectNodes("//*[local-name()='PackageReference']"))) {
        $include = $packageReference.GetAttribute('Include')

        if ([string]::IsNullOrWhiteSpace($include)) {
            continue
        }

        $versionAttribute = $packageReference.GetAttributeNode('Version')
        $version = Get-XmlElementValue -Element $packageReference -AttributeName 'Version'

        if (-not [string]::IsNullOrWhiteSpace($version) -and -not $Packages.ContainsKey($include)) {
            $Packages[$include] = $version
        }

        if ($null -ne $versionAttribute) {
            [void]$packageReference.RemoveAttribute('Version')
            $changed = $true
        }

        $versionElement = $packageReference.SelectSingleNode("./*[local-name()='Version']")

        if ($null -ne $versionElement) {
            [void]$packageReference.RemoveChild($versionElement)
            $changed = $true
        }
    }

    if ($changed) {
        Save-XmlDocument -Document $document -Path $ProjectFile.FullName -OmitXmlDeclaration
    }

    return $changed
}

$resolvedWorkingDir = (Resolve-Path -LiteralPath $WorkingDir -ErrorAction Stop).Path

if (-not (Test-Path -LiteralPath $resolvedWorkingDir -PathType Container)) {
    throw "O diretorio de trabalho '$WorkingDir' nao existe ou nao e um diretorio."
}

Get-Command dotnet -ErrorAction Stop | Out-Null

$locationPushed = $false

try {
    Push-Location -LiteralPath $resolvedWorkingDir
    $locationPushed = $true

    $projectFiles = @(
        Get-ChildItem -LiteralPath $resolvedWorkingDir -Recurse -File -Filter '*.csproj' -ErrorAction Stop |
            Where-Object { $_.FullName -notmatch '[\\/](bin|obj)([\\/]|$)' }
    )

    if ($projectFiles.Count -eq 0) {
        throw "Nenhum arquivo .csproj foi encontrado em '$resolvedWorkingDir'."
    }

    $solutionFiles = @(
        Get-ChildItem -LiteralPath $resolvedWorkingDir -Recurse -File -Filter '*.sln' -ErrorAction Stop
        Get-ChildItem -LiteralPath $resolvedWorkingDir -Recurse -File -Filter '*.slnx' -ErrorAction Stop
    ) | Where-Object { $_.FullName -notmatch '[\\/](bin|obj)([\\/]|$)' }
    $solutionFiles = @($solutionFiles)

    if ($solutionFiles.Count -gt 1) {
        throw "Mais de uma solucao (.sln/.slnx) foi encontrada. Informe um diretorio com uma unica solucao."
    }

    if ($solutionFiles.Count -eq 1) {
        $dotnetTarget = $solutionFiles[0].FullName
    }
    elseif ($projectFiles.Count -eq 1) {
        $dotnetTarget = $projectFiles[0].FullName
    }
    else {
        throw 'Foram encontrados varios projetos, mas nenhuma solucao. Crie ou informe uma solucao para definir o alvo do .NET.'
    }

    Write-Host '===============================================================' -ForegroundColor Cyan
    Write-Host '  Atualizacao para .NET 10 + Central Package Management (CPM)  ' -ForegroundColor Cyan
    Write-Host "  Diretorio de trabalho: $resolvedWorkingDir" -ForegroundColor Gray
    Write-Host '===============================================================' -ForegroundColor Cyan

    Write-Host "`n[1/6] Atualizando TargetFramework para net10.0..." -ForegroundColor Yellow

    $packagesDict = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cpmFile = Join-Path $resolvedWorkingDir 'Directory.Packages.props'

    if (Test-Path -LiteralPath $cpmFile -PathType Leaf) {
        Write-Host "`n[2/6] Carregando Directory.Packages.props existente..." -ForegroundColor Yellow

        $cpmDocument = Read-XmlDocument -Path $cpmFile

        foreach ($packageVersion in @($cpmDocument.SelectNodes("//*[local-name()='PackageVersion']"))) {
            $packageId = $packageVersion.GetAttribute('Include')
            $version = Get-XmlElementValue -Element $packageVersion -AttributeName 'Version'

            if (-not [string]::IsNullOrWhiteSpace($packageId) -and -not [string]::IsNullOrWhiteSpace($version)) {
                $packagesDict[$packageId] = $version
            }
        }

        Write-Host "Mantidos $($packagesDict.Count) pacotes ja centralizados." -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n[2/6] Criando nova estrutura CPM..." -ForegroundColor Yellow
        $cpmDocument = New-CentralPackageManagementDocument
    }

    foreach ($projectFile in $projectFiles) {
        if (Update-ProjectDocument -ProjectFile $projectFile -Packages $packagesDict) {
            Write-Host "Atualizado: $($projectFile.Name)" -ForegroundColor DarkGray
        }
    }

    Write-Host "`n[3/6] Migrando dependencias para Central Package Management..." -ForegroundColor Yellow

    $cpmChanged = Ensure-CentralPackageManagement -Document $cpmDocument
    if (Add-MissingPackageVersions -Document $cpmDocument -Packages $packagesDict) {
        $cpmChanged = $true
    }

    if ($cpmChanged -or -not (Test-Path -LiteralPath $cpmFile -PathType Leaf)) {
        Save-XmlDocument -Document $cpmDocument -Path $cpmFile
    }

    Write-Host "Directory.Packages.props atualizado com $($packagesDict.Count) pacotes." -ForegroundColor Green

    Write-Host "`n[4/6] Restaurando e atualizando pacotes NuGet..." -ForegroundColor Yellow

    Invoke-DotNet -Arguments @('restore', $dotnetTarget)
    Invoke-DotNet -Arguments @('clean', $dotnetTarget)

    $dotnetOutdatedSource = 'https://api.nuget.org/v3/index.json'
    $toolList = Get-GlobalDotNetToolList
    if ($toolList -match '(?im)^\s*dotnet-outdated-tool(?:\s|$)') {
        Invoke-DotNet -Arguments @('tool', 'update', '--global', 'dotnet-outdated-tool', '--source', $dotnetOutdatedSource)
    }
    else {
        Invoke-DotNet -Arguments @('tool', 'install', '--global', 'dotnet-outdated-tool', '--source', $dotnetOutdatedSource)
    }

    Invoke-DotNet -Arguments @('outdated', '-u', '--version-lock', 'Major')
    Invoke-DotNet -Arguments @('restore', $dotnetTarget)

    Write-Host "`n[5/6] Verificando compilacao da solucao..." -ForegroundColor Yellow
    Invoke-DotNet -Arguments @('build', $dotnetTarget, '--no-restore', '--configuration', 'Release')
    Write-Host "`n[SUCESSO] Solucao compilada com sucesso no .NET 10!" -ForegroundColor Green

    Write-Host "`n[6/6] Verificando vulnerabilidades de seguranca..." -ForegroundColor Yellow
    Invoke-DotNet -Arguments @('list', $dotnetTarget, 'package', '--vulnerable', '--include-transitive')

    Write-Host "`n=============================================================" -ForegroundColor Green
    Write-Host '  Migracao concluida com sucesso!' -ForegroundColor Green
    Write-Host '===============================================================' -ForegroundColor Green
}
catch {
    Write-Host "`n[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}
