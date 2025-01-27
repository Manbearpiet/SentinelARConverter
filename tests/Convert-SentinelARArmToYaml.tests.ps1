param(
    [Parameter()]
    [String]
    $exampleFilePath = "./tests/examples/Scheduled.json",
    [Parameter()]
    [String]
    $exampleMultipleFilePath = "./tests/examples/ScheduledMultiple.json",
    [Parameter()]
    [Switch]
    $RetainTestFiles = $false
)

BeforeDiscovery {
    if (Get-Module SentinelARConverter) {
        Remove-Module SentinelARConverter -Force
    }
    # Import the module for the tests
    $ModuleRoot = Split-Path -Path ./tests -Parent
    Import-Module -Name "$ModuleRoot/src/SentinelARConverter.psd1"

    # Multiple ART
    $DiscoveryARMTemplateMultipleContent = Get-Content $exampleMultipleFilePath -Raw
    $DiscoveryconvertedMultipleTemplateContent = $DiscoveryARMTemplateMultipleContent | ConvertFrom-Json
}

BeforeAll {

    # Import the module for the tests
    $ModuleRoot = Split-Path -Path ./tests -Parent
    Import-Module -Name "$ModuleRoot/src/SentinelARConverter.psd1"

    # Create a test output folder
    New-Item -ItemType Directory -Path "./tests/testOutput" -Force | Out-Null

    # Do fileconversion
    # Single ART
    $convertedExampleFilePath = $exampleFilePath -replace "\.json$", ".yaml"
    $ARMTemplateContent = Get-Content $exampleFilePath -Raw
    $outputPath = $convertedExampleFilePath -replace "/examples/", "/testOutput/"
    $convertedExampleFilePath -match "\w*\.yaml$"
    $convertedExampleFileName = $matches[0]

    # Multiple ART
    $convertedMultipleExampleFilePath = $exampleMultipleFilePath -replace "\.json$", ".yaml"
    $ARMTemplateMultipleContent = Get-Content $exampleMultipleFilePath -Raw
    $MultipleExampleFile = Get-Item $exampleMultipleFilePath
    $outputMultiplePath = $exampleMultipleFilePath -replace "/examples/", "/testOutput/"
    $convertedMultipleExampleFilePath -match "\w*\.yaml$"
    $convertedMultipleExampleFileName = $matches[0]
    $convertedMultipleTemplateContent = $ARMTemplateMultipleContent | ConvertFrom-Json
}

Describe "Convert-SentinelARArmToYaml" {

    BeforeEach {
        Get-ChildItem ./tests/testOutput/ | Remove-Item -Recurse -Force
        Get-ChildItem ./tests/examples -Filter *.yaml | Remove-Item -Force
    }

    AfterEach {
        if (-not $RetainTestFiles) {
            Get-ChildItem ./tests/testOutput/ | Remove-Item -Recurse -Force
            Get-ChildItem -Path ./tests/examples -Filter *.yaml | Remove-Item -Force
        }
    }

    Context "When no valid path was passed" -Tag Unit {
        It "Throws an error" {
            { Convert-SentinelARArmToYaml -Filename "C:\Not\A\Real\File.json" } | Should -Throw "File not found"
        }
    }
    Context "When no resources are present in the passed ARM template" -Tag Unit {

        It "Throws an error" {
            {
                $ARMTemplateContent |
                ConvertFrom-Json |
                Select-Object "`$schema", "contentVersion", "parameters" |
                ConvertTo-Json -Depth 99 |
                Convert-SentinelARArmToYaml -OutFile $outputPath
            } | Should -Throw "This template contains no Analytics Rules or resources"
        }
    }

    Context "If an invalid template id is provided in the analytics rule resources block" -Tag Unit {
        It "Creates a new guid" {
            Convert-SentinelARArmToYaml -Filename "./tests/examples/ScheduledBadGuid.json" -OutFile $outputPath

            $outputPath | Should -Not -FileContentMatch 'id: z-4a5f-4d27-8a26-b60a7952d5af'
        }
    }

    Context "If redundant ARM Properties are present in the rules" -Tag Unit {
        It "Removes the redundant ARM properties" {
            $outputPath = "./tests/testOutput/$convertedExampleFileName"

            $ARMTemplateContent | Convert-SentinelARArmToYaml -OutFile $outputPath

            $outputPath | Should -Not -FileContentMatch '^enabled: true'
        }
    }

    Context "When the template contains timespan values" -Tag Unit {

        It "Properly converts the units" {
            $outputPath = "./tests/testOutput/$convertedExampleFileName"

            $ARMTemplateContent | Convert-SentinelARArmToYaml -OutFile $outputPath

            $outputPath | Should -Not -FileContentMatch '^suppressionDuration: PT'
            $outputPath | Should -Not -FileContentMatch '^queryPeriod: PT'
            $outputPath | Should -Not -FileContentMatch '^queryFrequency: PT'
        }
    }

    Context "When specific propertynames/comparison properties are found on AR objects" -Tag Unit {

        BeforeDiscovery {
            $convertedJSON = Get-Content -Path $exampleFilePath -Raw | ConvertFrom-Json
            foreach ($resource in $convertedJSON["resources"]) {
                if (-not $resource.properties.ContainsKey("triggerOperator")) {
                    Write-Warning "This template does not contain a triggerOperator property. Cannot test conversion of comparison operators."
                    $CannotCheckComparisonOperators = $true
                }
            }
        }

        BeforeEach {
            $ARMTemplateContent = Get-Content -Path $exampleFilePath -Raw
            $ARMTemplateContent | Convert-SentinelARArmToYaml -OutFile $outputPath
        }

        It "Properly converts the propertynames" {

            $outputPath | Should -Not -FileContentMatch '^displayName'
            $outputPath | Should -Not -FileContentMatch '^alertRuleTemplateName'
            $outputPath | Should -Not -FileContentMatch '^templateVersion'
            $outputPath | Should -Not -FileContentMatch '^techniques'
        }

        It "Properly converts the comparison operators" -Skip:$CannotCheckComparisonOperators {
            $outputPath | Should -Not -FileContentMatch 'GreaterThan$'
            $outputPath | Should -Not -FileContentMatch 'Equals$'
            $outputPath | Should -Not -FileContentMatch 'GreaterThanOrEqual$'
            $outputPath | Should -Not -FileContentMatch 'LessThan$'
            $outputPath | Should -Not -FileContentMatch 'LessThanOrEqual$'
        }
    }
    Context "Properly handles Force situations" -Tag Unit {
        BeforeEach {
            "this is not an ART" | Out-File -FilePath $outputPath -Force
        }

        It "Shouldn't overwrites existing files when Force is not used" {
            { Convert-SentinelARArmToYaml -OutFile $outputPath -Filename $exampleFilePath } | Should -Throw
            $outputPath | Should -FileContentMatch "^this is not an ART"
        }
        It "Shouldn't overwrites existing files when Force is not used and throw an exception" {
            { Convert-SentinelARArmToYaml -OutFile $outputPath -Filename $exampleFilePath } | Should -Throw
        }
        It "Should overwrites existing files when Force is used and shouldn't throw an exception" {
            { Convert-SentinelARArmToYaml -OutFile $outputPath -Filename $exampleFilePath -Force } | Should -Not -Throw
            $outputPath | Should -Not -FileContentMatch "^this is not an ART"
        }
        It "Should overwrites existing files when Force is used and shouldn't throw an exception" {
            { Convert-SentinelARArmToYaml -OutFile $outputPath -Filename $exampleFilePath -Force } | Should -Not -Throw
        }
    }
}

Describe "Single File Testcases" {

    BeforeEach {
        Get-ChildItem ./tests/testOutput/ | Remove-Item -Recurse -Force
        Get-ChildItem ./tests/examples -Filter *.yaml | Remove-Item -Force
    }

    AfterEach {
        if (-not $RetainTestFiles) {
            Get-ChildItem ./tests/testOutput/ | Remove-Item -Recurse -Force
            Get-ChildItem -Path ./tests/examples -Filter *.yaml | Remove-Item -Force
        }
    }

    Context "When converting a Sentinel Alert Rule ARM template to YAML" -Tag Integration {
        It "Converts a Scheduled Query Alert Sentinel Alert Rule ARM template to a YAML-file" {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleFilePath
                OutFile  = "./tests/testOutput/$convertedExampleFileName"
            }

            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat
            Get-Content $convertSentinelARArmToYamlSplat.OutFile | Should -Not -BeNullOrEmpty
        }
    }

    Context "If UseOriginalFilename was passed" -Tag Integration {
        It "Creates a yaml file in the same folder as the ARM template" {
            $convertSentinelARArmToYamlSplat = @{
                Filename            = $exampleFilePath
                UseOriginalFilename = $true
            }

            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat
            $convertedExampleFilePath | Should -Exist
        }

        It "Should use the original filename" {
            $convertSentinelARArmToYamlSplat = @{
                Filename            = $exampleFilePath
                UseOriginalFilename = $true
            }

            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat

            $path = $convertSentinelARArmToYamlSplat.Filename -replace "\.json$", ".yaml"

            Get-ChildItem $convertedExampleFilePath | Should -Match $convertedExampleFileName
        }
    }

    Context "If UseDisplayNameAsFilename was passed" -Tag Integration {
        It "Creates a yaml file in the same folder as the ARM template with the display name as filename" {
            $convertSentinelARArmToYamlSplat = @{
                Filename                 = "./tests/examples/Scheduled.json"
                UseDisplayNameAsFilename = $true
            }
            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat

            "./tests/examples/AzureWAFMatchingForLog4jVulnCVE202144228.yaml" | Should -Exist
            Remove-Item "./tests/examples/AzureWAFMatchingForLog4jVulnCVE202144228.yaml" -Force
        }
    }

    Context "If UseIdAsFilename was passed" -Tag Integration {
        It "Creates a yaml file in the same folder as the ARM template with the id as filename" {
            $convertSentinelARArmToYamlSplat = @{
                Filename        = "./tests/examples/Scheduled.json"
                UseIdAsFilename = $true
            }

            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat

            "./tests/examples/6bb8e22c-4a5f-4d27-8a26-b60a7952d5af.yaml" | Should -Exist
            Remove-Item "./tests/examples/6bb8e22c-4a5f-4d27-8a26-b60a7952d5af.yaml" -Force
        }
    }
    Context "If an ARM template file content is passed via pipeline" -Tag Integration {
        It "Should convert a Scheduled Query Alert Sentinel Alert Rule ARM template to a YAML file" {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleFilePath
                OutFile  = $convertedExampleFileName
            }
            Get-Content -Path $convertSentinelARArmToYamlSplat.Filename -Raw | Convert-SentinelARArmToYaml -OutFile $outputPath
            Test-Path -Path $outputPath | Should -Be $True
        }
    }

    Context "If neither OutFile or UseOriginalFilename is passed" -Tag Integration {
        It "Outputs YAML to the console" {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleFilePath
            }

            $output = (Get-Content -Path $convertSentinelARArmToYamlSplat.Filename -Raw | Convert-SentinelARArmToYaml)
            $output | Should -Not -BeNullOrEmpty
            Get-ChildItem -Path ./tests -Recurse -Filter $convertedExampleFileName | Should -BeNullOrEmpty
        }
    }
}

Describe "Multi File Testcases" -Skip:(($DiscoveryconvertedMultipleTemplateContent.resources).Count -lt 2) {

    BeforeEach {
        Get-ChildItem ./tests/testOutput/ -Filter *.yaml | Remove-Item -Recurse -Force
        Get-ChildItem ./tests/examples -Filter *.yaml | Remove-Item -Force
    }
    AfterEach {
        if (-not $RetainTestFiles) {
            Get-ChildItem ./tests/testOutput/ | Remove-Item -Recurse -Force
            Get-ChildItem -Path ./tests/examples -Filter *.yaml | Remove-Item -Force
        }
    }

    Context "When converting a Sentinel Alert Rule ARM template with multiple alerts to YAML" -Tag Integration {
        BeforeDiscovery {
            # There always will be at least once file created, but we don't name the first one with a suffix
            # By subtracting 1 from the amount of resources, we can use that as a range for the expected amount of files
            $DiscoveryExpectedFilesAmount = (0..($DiscoveryconvertedMultipleTemplateContent.resources.Count - 1))
        }
        BeforeEach {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleMultipleFilePath
                OutFile  = "./tests/testOutput/$convertedMultipleExampleFileName"
            }
            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat
        }
        It "Converts to multiple YAML-file with the specified suffix (Alert #<_>)" -ForEach $DiscoveryExpectedFilesAmount {
            if ($_ -eq 0) {
                Get-Content ($convertSentinelARArmToYamlSplat.OutFile -replace "\.yaml$", ".yaml") | Should -Not -BeNullOrEmpty
            } else {
                Get-Content ($convertSentinelARArmToYamlSplat.OutFile -replace "\.yaml$", "_$_.yaml") | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "If UseOriginalFilename was passed" -Tag Integration {
        BeforeDiscovery {
            # There always will be at least once file created, but we don't name the first one with a suffix
            # By subtracting 1 from the amount of resources, we can use that as a range for the expected amount of files
            $DiscoveryExpectedFilesAmount = (0..($DiscoveryconvertedMultipleTemplateContent.resources.Count - 1))

            $DiscoveryconvertSentinelARArmToYamlSplat = @{
                Filename            = $exampleMultipleFilePath
                UseOriginalFilename = $true
            }
            Convert-SentinelARArmToYaml @DiscoveryconvertSentinelARArmToYamlSplat

            $DiscoveryFile = Get-Item $exampleMultipleFilePath
            $Discoveryfilenames = @(foreach ($entry in ($DiscoveryExpectedFilesAmount -NE 0)) {
                    $DiscoveryFile.BaseName + "_$entry" + ".yaml"
                }
            )
            $Discoveryfilenames += $DiscoveryFile.BaseName + ".yaml"
            Get-ChildItem -Path (Split-Path $exampleMultipleFilePath -Parent) -Filter *.yaml | Remove-Item -Force
        }

        BeforeEach {
            $convertSentinelARArmToYamlSplat = @{
                Filename            = $exampleMultipleFilePath
                UseOriginalFilename = $true
            }
            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat
            $exampleParent = $exampleMultipleFilePath | Split-Path -Parent
        }

        AfterAll {
            if (-not $RetainTestFiles) {
                Get-ChildItem ./tests/testOutput/ | Remove-Item -Recurse -Force
                Get-ChildItem -Path ./tests/examples -Filter *.yaml | Remove-Item -Force
            }
        }
        It "Creates a yaml file in the same folder as the ARM template (<_>)" -ForEach $Discoveryfilenames {
            Get-Content (Join-Path -Path $exampleParent -ChildPath $_) | Should -Not -BeNullOrEmpty
        }

        It "Should use the original filename (<_>)" -ForEach $Discoveryfilenames {
            (Get-ChildItem $exampleParent -Filter *.yaml ).Name | Should -Match "^$($MultipleExampleFile.BaseName)"
        }

        It "Should suffix the original filename with a number if multiple yaml files are created (<_>)" -ForEach $Discoveryfilenames {
            (Get-ChildItem $exampleParent/* -Filter *.yaml -Exclude $convertedMultipleExampleFileName).Name | Should -Match "^$($MultipleExampleFile.BaseName)"
        }
    }

    Context "If UseDisplayNameAsFilename was passed" -Tag Integration {
        BeforeDiscovery {
            $DiscoveryfileNames = foreach ($displayname in $DiscoveryconvertedMultipleTemplateContent.resources.properties.displayName) {
                # Use the display name of the Analytics Rule as filename
                $FileName = $displayname -Replace '[^0-9A-Z]', ' '
                # Convert To CamelCase
                ((Get-Culture).TextInfo.ToTitleCase($FileName) -Replace ' ') + '.yaml'
            }
        }
        BeforeEach {
            $convertSentinelARArmToYamlSplat = @{
                Filename                 = $exampleMultipleFilePath
                UseDisplayNameAsFilename = $true
            }
            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat
            $exampleParent = $exampleMultipleFilePath | Split-Path -Parent

            $fileNames = foreach ($displayname in $convertedMultipleTemplateContent.resources.properties.displayName) {
                # Use the display name of the Analytics Rule as filename
                $FileName = $displayname -Replace '[^0-9A-Z]', ' '
                # Convert To CamelCase
                ((Get-Culture).TextInfo.ToTitleCase($FileName) -Replace ' ') + '.yaml'
            }
        }
        It "Creates yaml files in the same folder as the ARM template with the display name as filename (<_>)" -ForEach $DiscoveryfileNames {
            (Get-ChildItem $exampleParent/* -Filter *.yaml -Exclude $convertedMultipleExampleFileName).Name | Should -BeIn $fileNames
        }
    }
    Context "If UseIdAsFilename was passed" -Tag Integration {
        BeforeDiscovery {
            $DiscoveryfileNames = foreach ($displayname in $DiscoveryconvertedMultipleTemplateContent.resources.properties.displayName) {
                # Use the display name of the Analytics Rule as filename
                $FileName = $displayname -Replace '[^0-9A-Z]', ' '
                # Convert To CamelCase
                ((Get-Culture).TextInfo.ToTitleCase($FileName) -Replace ' ')
            }
        }
        BeforeEach {
            $convertSentinelARArmToYamlSplat = @{
                Filename        = $exampleMultipleFilePath
                UseIdAsFilename = $true
            }
            Convert-SentinelARArmToYaml @convertSentinelARArmToYamlSplat
            $exampleParent = $exampleMultipleFilePath | Split-Path -Parent
            [string[]]$ids = @(
                foreach ($resource in $convertedMultipleTemplateContent.resources) {
                    $resource.id -match "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | Out-Null
                    $matches[0]
                }
            )
        }
        It "Creates a yaml file in the same folder as the ARM template with the id as filename (<_>)" -ForEach $DiscoveryfileNames {
            (Get-ChildItem -Path $exampleParent -Filter *.yaml).BaseName | Should -BeIn $ids
        }
    }

    Context "If an ARM template file content, containing multiple ARTs, is passed via pipeline using OutFile" -Tag Integration {

        BeforeDiscovery {
            # There always will be at least once file created, but we don't name the first one with a suffix
            # By subtracting 1 from the amount of resources, we can use that as a range for the expected amount of files
            $DiscoveryExpectedFilesAmount = (0..($DiscoveryconvertedMultipleTemplateContent.resources.Count - 1))
        }
        BeforeEach {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleMultipleFilePath
                OutFile  = "./tests/testOutput/$convertedMultipleExampleFileName"
            }
            Get-Content $convertSentinelARArmToYamlSplat.Filename -Raw | Convert-SentinelARArmToYaml -OutFile $convertSentinelARArmToYamlSplat.OutFile -Force
        }
        It "Converts to multiple YAML-file with the specified suffix (Alert #<_> <convertedMultipleExampleFileName>)" -ForEach $DiscoveryExpectedFilesAmount {
            if ($_ -eq 0) {
                Get-Content ($convertSentinelARArmToYamlSplat.OutFile -replace "\.yaml$", ".yaml") | Should -Not -BeNullOrEmpty
            } else {
                Get-Content ($convertSentinelARArmToYamlSplat.OutFile -replace "\.yaml$", "_$_.yaml") | Should -Not -BeNullOrEmpty
            }
        }
    }
    Context "If an ARM template file content, containing multiple ARTs, is passed via pipeline using UseDisplayNameAsFilename" -Tag Integration {

        BeforeDiscovery {
            $DiscoveryfileNames = foreach ($displayname in $DiscoveryconvertedMultipleTemplateContent.resources.properties.displayName) {
                # Use the display name of the Analytics Rule as filename
                $FileName = $displayname -Replace '[^0-9A-Z]', ' '
                # Convert To CamelCase
                ((Get-Culture).TextInfo.ToTitleCase($FileName) -Replace ' ') + '.yaml'
            }
        }
        BeforeEach {
            Get-Content $exampleMultipleFilePath -Raw | Convert-SentinelARArmToYaml -UseDisplayNameAsFilename -Directory "./tests/testOutput"
            $exampleParent = $exampleMultipleFilePath | Split-Path -Parent
            $testOutputPath = $exampleMultipleFilePath | Split-Path -Parent | Split-Path -Parent | Join-Path -ChildPath "testOutput"

            $fileNames = foreach ($displayname in $convertedMultipleTemplateContent.resources.properties.displayName) {
                # Use the display name of the Analytics Rule as filename
                $FileName = $displayname -Replace '[^0-9A-Z]', ' '
                # Convert To CamelCase
                ((Get-Culture).TextInfo.ToTitleCase($FileName) -Replace ' ') + '.yaml'
            }
        }
        It "Creates yaml files in the same folder as the ARM template with the display name as filename (<_>)" -ForEach $DiscoveryfileNames {
            (Get-ChildItem $testOutputPath/* -Filter *.yaml -Exclude $convertedMultipleExampleFileName).Name | Should -BeIn $fileNames
        }
    }

    Context "If an ARM template file content, containing multiple ARTs, is passed via pipeline using UseIdAsFilename" -Tag Integration {

        BeforeDiscovery {
            $DiscoveryfileNames = foreach ($displayname in $DiscoveryconvertedMultipleTemplateContent.resources.properties.displayName) {
                # Use the display name of the Analytics Rule as filename
                $FileName = $displayname -Replace '[^0-9A-Z]', ' '
                # Convert To CamelCase
                ((Get-Culture).TextInfo.ToTitleCase($FileName) -Replace ' ')
            }
        }
        BeforeEach {
            Get-Content $exampleMultipleFilePath -Raw | Convert-SentinelARArmToYaml -UseIdAsFilename -Directory "./tests/testOutput"
            $exampleParent = $exampleMultipleFilePath | Split-Path -Parent
            $testOutputPath = $exampleMultipleFilePath | Split-Path -Parent | Split-Path -Parent | Join-Path -ChildPath "testOutput"


            [string[]]$ids = @(
                foreach ($resource in $convertedMultipleTemplateContent.resources) {
                    $resource.id -match "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | Out-Null
                    $matches[0]
                }
            )
        }
        It "Creates yaml files in the same folder as the ARM template with the display name as filename (<_>)" -ForEach $DiscoveryfileNames {
            (Get-ChildItem $testOutputPath/* -Filter *.yaml -Exclude $convertedMultipleExampleFileName).BaseName | Should -BeIn $ids
        }
    }

    Context "If neither OutFile or UseOriginalFilename is passed" -Tag Integration {
        It "Outputs YAML to the console (single alert)" {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleFilePath
            }
            $output = (Get-Content -Path $convertSentinelARArmToYamlSplat.Filename -Raw | Convert-SentinelARArmToYaml)
            $output | Should -Not -BeNullOrEmpty
            Get-ChildItem -Path ./tests -Recurse -Filter $convertedExampleFileName | Should -BeNullOrEmpty
        }
        It "Outputs YAML to the console (multi alert)" {
            $convertSentinelARArmToYamlSplat = @{
                Filename = $exampleMultipleFilePath
            }
            $output = (Get-Content -Path $convertSentinelARArmToYamlSplat.Filename -Raw | Convert-SentinelARArmToYaml)
            $output[0] | Should -Not -BeNullOrEmpty
            $output[1] | Should -Not -BeNullOrEmpty
            Get-ChildItem -Path ./tests -Recurse -Filter $convertedExampleFileName | Should -BeNullOrEmpty
        }
    }
}

Describe "Simple example tests" {
    Context "Single example tests" -Tag Integration {
        BeforeAll {
            New-Item TestDrive:/Single/ -ItemType Directory | Out-Null
            Copy-Item -Path $exampleFilePath -Destination TestDrive:/Single/
        }
        AfterEach {
            Remove-Item -Path "TestDrive:/Single/*" -Include *.yaml -Force
        }
        It "No Pipeline and OutFile" {
            Convert-SentinelARArmToYaml -Filename "TestDrive:/Single/Scheduled.json" -OutFile "TestDrive:/Single/Scheduled.yaml"
            Get-ChildItem -Path "TestDrive:/Single/*" -Include *.yaml | Should -HaveCount 1
        }
        It "No Pipeline and UseOriginalFilename" {
            Convert-SentinelARArmToYaml -Filename "TestDrive:/Single/Scheduled.json" -UseOriginalFilename
            Get-ChildItem -Path "TestDrive:/Single/*" -Include *.yaml | Should -HaveCount 1
        }
        It "Pipeline and OutFile" {
            Get-Content -Path "TestDrive:/Single/Scheduled.json" -Raw | Convert-SentinelARArmToYaml -OutFile "TestDrive:/Single/Scheduled.yaml"
            Get-ChildItem -Path "TestDrive:/Single/*" -Include *.yaml | Should -HaveCount 1
        }
    }
    Context "Multiple example tests" -Tag Integration {
        BeforeAll {
            New-Item TestDrive:/Multiple/ -ItemType Directory | Out-Null
            Copy-Item -Path $exampleMultipleFilePath -Destination TestDrive:/Multiple/
        }
        AfterEach {
            Remove-Item -Path "TestDrive:/Multiple/*" -Include *.yaml -Force
        }
        It "No Pipeline and Outfile" {
            Convert-SentinelARArmToYaml -Filename "TestDrive:/Multiple/ScheduledMultiple.json" -OutFile "TestDrive:/Multiple/ScheduledMultiple.yaml"
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
        It "No Pipeline and UseOriginalFilename" {
            Convert-SentinelARArmToYaml -Filename "TestDrive:/Multiple/ScheduledMultiple.json" -UseOriginalFilename
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
        It "No Pipeline and UseDisplayNameAsFilename" {
            Convert-SentinelARArmToYaml -Filename "TestDrive:/Multiple/ScheduledMultiple.json" -UseDisplayNameAsFilename
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
        It "No Pipeline and UseIdAsFilename" {
            Convert-SentinelARArmToYaml -Filename "TestDrive:/Multiple/ScheduledMultiple.json" -UseIdAsFilename
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
        It "Pipeline and OutFile" {
            Get-Content -Path "TestDrive:/Multiple/ScheduledMultiple.json" -Raw | Convert-SentinelARArmToYaml -OutFile "TestDrive:/Multiple/ScheduledMultiple.yaml"
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
        It "Pipeline and UseDisplayNameAsFilename" {
            Get-Content -Path "TestDrive:/Multiple/ScheduledMultiple.json" -Raw | Convert-SentinelARArmToYaml -UseDisplayNameAsFilename -Directory "TestDrive:/Multiple/"
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
        It "Pipeline and UseIdAsFilename" {
            Get-Content -Path "TestDrive:/Multiple/ScheduledMultiple.json" -Raw | Convert-SentinelARArmToYaml -UseIdAsFilename -Directory "TestDrive:/Multiple/"
            Get-ChildItem -Path "TestDrive:/Multiple/*" -Include *.yaml | Should -HaveCount 2
        }
    }
}

AfterAll {
    if (-not $RetainTestFiles) {
        Remove-Item -Path "./tests/testOutput/" -Recurse -Force
    }
    if ( Get-Module -Name SentinelARConverter ) {
        Remove-Module -Name SentinelARConverter -Force
    }
}

