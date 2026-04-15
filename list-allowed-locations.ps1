$Location = (az policy assignment list --query "[?name == 'sys.regionrestriction'].parameters.listOfAllowedLocations.value" | ConvertFrom-Json)[0]
