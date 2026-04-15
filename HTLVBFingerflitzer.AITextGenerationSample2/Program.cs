using OpenAI.Chat;
using Azure.Identity;
using Azure.AI.OpenAI;

var endpoint = new Uri("https://cloud-mmm1uati-eastus2.cognitiveservices.azure.com/");
var deploymentName = "gpt-5.1-chat";

AzureOpenAIClient azureClient = new(
    endpoint,
    new DefaultAzureCredential());
ChatClient chatClient = azureClient.GetChatClient(deploymentName);

var requestOptions = new ChatCompletionOptions()
{
    MaxOutputTokenCount = 4096,
    Temperature = 1.0f,
    TopP = 1.0f,

};

List<ChatMessage> messages = new List<ChatMessage>()
{
    new SystemChatMessage("You are a helpful assistant."),
    new UserChatMessage("I am going to Paris, what should I see?"),
};

var response = chatClient.CompleteChat(messages, requestOptions);
Console.WriteLine(response.Value.Content[0].Text);