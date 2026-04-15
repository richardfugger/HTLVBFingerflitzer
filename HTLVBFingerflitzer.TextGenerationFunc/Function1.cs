using Dapper;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Npgsql;
using OpenAI.Chat;
using Azure.AI.OpenAI;
using Azure.Identity;

namespace HTLVBFingerflitzer.TextGenerationFunc;

public class Function1
{
    private readonly ILogger _logger;
    private readonly PostgreSQLConnectionFactory _dbConnectionFactory = new("Server=db-fingerflitzer-cloudcomputing242501.postgres.database.azure.com;Database=fingerflitzer;Port=5432;User Id=CloudComputing2425-01@htlvb.at;Ssl Mode=Require;");
    private readonly ChatClient _chatClient;

    public Function1(ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<Function1>();

        var endpoint = new Uri("https://ai-fingerflitzer-cloudcomputing242501.cognitiveservices.azure.com/");
        var deploymentName = "gpt-5.1-chat";

        var azureClient = new AzureOpenAIClient(endpoint, new DefaultAzureCredential());
        _chatClient = azureClient.GetChatClient(deploymentName);
    }

    [Function("Function1")]
    public void Run([TimerTrigger("0 */2 * * * *")] TimerInfo myTimer)
    {
        _logger.LogInformation("C# Timer trigger function executed at: {executionTime}", DateTime.Now);

        using var dbConnection = _dbConnectionFactory.Create();

        // 1. Tage suchen, für die ein Text generiert werden muss
        //   (Text soll für die nächsten 7 Tage vorhanden sein)
        List<DateOnly> daysWithoutGeneratedText = GetDaysWithoutGeneratedText(dbConnection);
        if (daysWithoutGeneratedText.Count == 0)
        {
            _logger.LogInformation("No dates without texts found");
            return;
        }
        foreach (DateOnly d in daysWithoutGeneratedText)
        {
            _logger.LogInformation(d.ToString());
        }
        // 2. Texte generieren
        List<(DateOnly, string)> texts = GenerateTexts(daysWithoutGeneratedText);
        // 3. Texte in DB speichern
        SaveTexts(dbConnection, texts);

        _logger.LogInformation("Generated and saved {count} texts", texts.Count);
    }

    private List<DateOnly> GetDaysWithoutGeneratedText(NpgsqlConnection connection)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var next7Days = Enumerable
            .Range(0, 7)
            .Select(i => today.AddDays(i))
            .ToList();

        var start = today.ToDateTime(TimeOnly.MinValue);
        var end = today.AddDays(6).ToDateTime(TimeOnly.MinValue);

        var existingDates = connection.Query<DateOnly>(
            @"SELECT challenge_date
              FROM challenges
              WHERE challenge_date >= @start AND challenge_date <= @end",
            new
            {
                start,
                end
            }
        ).ToHashSet();

        var missingDates = next7Days
            .Where(d => !existingDates.Contains(d))
            .ToList();

        return missingDates;
    }

    private List<(DateOnly date, string text)> GenerateTexts(List<DateOnly> dates)
    {
        var result = new List<(DateOnly, string)>();

        foreach (var date in dates)
        {
            var messages = new List<ChatMessage>()
        {
            new SystemChatMessage("You generate short typing practice texts."),
            new UserChatMessage("Generate a short typing training text (max 200 characters). No line breaks.")
        };

            var response = _chatClient.CompleteChat(messages);

            var text = response.Value.Content[0].Text.Trim();

            result.Add((date, text));
        }

        return result;
    }

    private void SaveTexts(NpgsqlConnection connection, List<(DateOnly date, string text)> texts)
    {
        foreach (var (date, text) in texts)
        {
            connection.Execute(
                @"INSERT INTO challenges (challenge_date, text)
              VALUES (@Date, @Text)
              ON CONFLICT (challenge_date) DO NOTHING",
                new { Date = date, Text = text });
        }
    }
}

