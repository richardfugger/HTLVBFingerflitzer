az login
gh auth login

$UserName = ((az ad signed-in-user show | ConvertFrom-Json).userPrincipalName -replace '@.*$', '' -replace '\W', '').ToLower()
$GitHubRepositoryName = "richardfugger/HTLVBFingerflitzer"
$Location = (az policy assignment list --query "[?name == 'sys.regionrestriction'].parameters.listOfAllowedLocations.value" | ConvertFrom-Json)[0]
$Location = "norwayeast"
az group create --name rg-fingerflitzer --location $Location | Out-Null

az appservice plan create `
  --name asp-fingerflitzer `
  --sku P0V3 `
  --is-linux `
  --resource-group rg-fingerflitzer | Out-Null

az webapp create `
  --name wa-fingerflitzer-$UserName `
  --runtime DOTNETCORE:8.0 `
  --assign-identity `
  --https-only true `
  --public-network-access Enabled `
  --plan asp-fingerflitzer `
  --resource-group rg-fingerflitzer | Out-Null

$SubscriptionId = (az account show | ConvertFrom-Json).id
$ServicePrincipalSecret = az ad sp create-for-rbac `
  --name "gh-action-to-deploy-fingerflitzer-webapp-$UserName" `
  --role contributor `
  --scopes "/subscriptions/$SubscriptionId/resourceGroups/rg-fingerflitzer/providers/Microsoft.Web/sites/wa-fingerflitzer-$UserName" `
  --json-auth

"$ServicePrincipalSecret" | gh secret set AZURE_CREDENTIALS `
  --repo $GitHubRepositoryName

az webapp deployment slot create `
  --slot staging `
  --name wa-fingerflitzer-$UserName `
  --resource-group rg-fingerflitzer

az webapp config appsettings set `
  --settings "DailyChallenge__Type=db-text" "DailyChallenge__ConnectionString=Server=db-fingerflitzer-$UserName.postgres.database.azure.com;Database=fingerflitzer;Port=5432;User Id=aad_fingerflitzer_webapp_to_db;Ssl Mode=Require;" `
  --slot staging `
  --name wa-fingerflitzer-$UserName `
  --resource-group rg-fingerflitzer

gh workflow run publish-fingerflitzer-web-app.yml `
  --repo $GitHubRepositoryName

# Allow access from web app to database
# see https://learn.microsoft.com/en-us/azure/app-service/tutorial-connect-msi-azure-database
az extension add --name serviceconnector-passwordless --upgrade
az webapp connection create postgres-flexible `
  --connection fingerflitzer_webapp_to_db `
  --resource-group rg-fingerflitzer `
  --name wa-fingerflitzer-$UserName `
  --target-resource-group rg-fingerflitzer `
  --server db-fingerflitzer-$UserName `
  --database fingerflitzer `
  --system-identity `
  --client-type dotnet | Out-Null
az webapp connection create postgres-flexible `
  --connection fingerflitzer_webapp_to_db `
  --resource-group rg-fingerflitzer `
  --name wa-fingerflitzer-$UserName `
  --slot "staging" `
  --target-resource-group rg-fingerflitzer `
  --server db-fingerflitzer-$UserName `
  --database fingerflitzer `
  --system-identity `
  --client-type dotnet | Out-Null

$WebApp = az webapp show `
  --name wa-fingerflitzer-$UserName `
  --resource-group rg-fingerflitzer | ConvertFrom-Json
$WebAppStagingSlot = az webapp deployment slot list `
  --resource-group rg-fingerflitzer `
  --name wa-fingerflitzer-$UserName `
  --query "[?name=='staging']" | ConvertFrom-Json

$ReplyUrls = @(
  "https://localhost/signin-oidc"
  "https://$($WebApp.defaultHostName)/signin-oidc"
  "https://$($WebAppStagingSlot.defaultHostName)/signin-oidc"
)
$AppRegistration = az ad app create --display-name Fingerflitzer-$UserName `
  --web-redirect-uris $ReplyUrls | ConvertFrom-Json

$AppSecret = az ad app credential reset --id $AppRegistration.id `
  --display-name Dev `
  --append | ConvertFrom-Json

az webapp config appsettings set `
  --settings "AzureAd__ClientId=$($AppRegistration.appId)" "AzureAd__ClientSecret=$($AppSecret.password)" `
  --slot staging `
  --name wa-fingerflitzer-$UserName `
  --resource-group rg-fingerflitzer
    
az webapp config appsettings set `
  --settings "AzureAd__ClientId=$($AppRegistration.appId)" "AzureAd__ClientSecret=$($AppSecret.password)" `
  --name wa-fingerflitzer-$UserName `
  --resource-group rg-fingerflitzer

dotnet user-secrets --project .\HTLVBFingerflitzer.Web\ set AzureAd:ClientSecret $($AppSecret.password)

Write-Host "### Web app: https://$($WebApp.defaultHostName)"
Write-Host "### Web app staging slot: https://$($WebAppStagingSlot.defaultHostName)"

Write-Host "### App registration:"
Write-Host "* Client id: $($AppSecret.appId)"
Write-Host "* Tenant id: $($AppSecret.tenant)"
Write-Host "* Client secret: $($AppSecret.password)"


az group delete --name rg-fingerflitzer --no-wait
$ServicePrincipal = az ad sp list --display-name "gh-action-to-deploy-fingerflitzer-webapp-$UserName" `
  | ConvertFrom-Json
az ad sp delete --id $ServicePrincipal.id


