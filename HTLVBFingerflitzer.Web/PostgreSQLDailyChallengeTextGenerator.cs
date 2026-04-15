using Azure.Identity;
using Dapper;
using Npgsql;

public class PostgreSQLConnectionFactory(string connectionStringTemplate)
{
    public NpgsqlConnection Create()
    {
        NpgsqlConnectionStringBuilder builder = new(connectionStringTemplate);
        if (builder.Password != null)
        {
            return new NpgsqlConnection(builder.ConnectionString);
        }
        Azure.Core.AccessToken accessToken = new DefaultAzureCredential().GetToken(
            new Azure.Core.TokenRequestContext([
                "https://ossrdbms-aad.database.windows.net/.default"
            ])
        );
        builder.Password = accessToken.Token;
        return new NpgsqlConnection(builder.ConnectionString);
    }
}

public class PostgreSQLDailyChallengeTextGenerator(
    PostgreSQLConnectionFactory connectionFactory,
    TimeProvider timeProvider) : IDailyChallengeTextGenerator
{
    public async Task<string> GetDailyChallengeTextAsync()
    {
        using NpgsqlConnection dbConnection = connectionFactory.Create();
        return await dbConnection.QuerySingleAsync<string>(
            $"SELECT text FROM challenges WHERE challenge_date = @Date",
            new { Date = timeProvider.GetLocalNow().Date });
    }
}