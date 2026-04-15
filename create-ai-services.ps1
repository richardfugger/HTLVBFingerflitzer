<#
az provider register --namespace Microsoft.CognitiveServices
#>

$UserName = ((az ad signed-in-user show | ConvertFrom-Json).userPrincipalName -replace '@.*$','' -replace '\W','').ToLower()
$AllowedLocations = az policy assignment list --query "[?name == 'sys.regionrestriction'].parameters.listOfAllowedLocations.value[]" | ConvertFrom-Json
$Location =
    @("norwayeast", "polandcentral", "swedencentral", "francecentral", "swedencentral") `
    | Where-Object { $AllowedLocations.Count -eq 0 -or $AllowedLocations -contains $_ } `
    | Select-Object -First 1
if (-not $Location) {
    throw "No location found."
}

az group create --name rg-fingerflitzer --location $Location | Out-Null

az cognitiveservices account create `
    --name ai-fingerflitzer-$UserName `
    --resource-group rg-fingerflitzer `
    --kind AIServices `
    --sku S0 `
    --location $Location `
    --custom-domain ai-fingerflitzer-$UserName | Out-Null

$Models = az cognitiveservices account list-models `
    --name ai-fingerflitzer-$UserName `
    --resource-group rg-fingerflitzer `
    | ConvertFrom-Json
$Model = $Models `
    | Where-Object name -Eq gpt-5.1-chat `
    | Sort-Object version -Descending `
    | Select-Object -First 1
$ModelSku = $Model.skus[0]

az cognitiveservices account deployment create `
    --name ai-fingerflitzer-$UserName `
    --resource-group rg-fingerflitzer `
    --deployment-name $Model.name `
    --model-name $ModelSku.usageName.Split('.', 3)[-1] `
    --model-version $Model.version `
    --model-format $Model.format `
    --sku-capacity $ModelSku.capacity.default `
    --sku-name $ModelSku.name | Out-Null
