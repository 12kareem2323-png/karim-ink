using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
namespace KarimEldamatyWindows;
public sealed class CraftConnection
{
    public string Endpoint { get; set; } = "";
    public string BearerToken { get; set; } = "";
    public Uri BaseUri
    {
        get
        {
            var value = (Endpoint ?? "").Trim().TrimEnd('/');
            if(value.Contains('%')||value.Contains('\\')||!Uri.TryCreate(value,UriKind.Absolute,out var uri)||uri.Scheme!="https"||uri.Host.ToLowerInvariant()!="connect.craft.do"||!uri.IsDefaultPort||uri.UserInfo.Length>0||uri.Query.Length>0||uri.Fragment.Length>0||uri.AbsolutePath.Contains('%')) throw new ArgumentException("Use the API URL from Craft's Imagine tab: https://connect.craft.do/link/…/api/v1.");
            var parts=uri.AbsolutePath.Split('/',StringSplitOptions.RemoveEmptyEntries);if(parts.Length!=4||parts[0]!="link"||parts[2]!="api"||parts[3]!="v1"||!ValidIdentifier(parts[1]))throw new ArgumentException("Use the API URL from Craft's Imagine tab: https://connect.craft.do/link/…/api/v1.");return uri;
        }
    }
    public static bool ValidIdentifier(string value)=>value is {Length: >0 and <=200}&&value.All(c=>char.IsAsciiLetterOrDigit(c)||c is '-' or '_');
    internal void Validate() { _=BaseUri;BearerToken=(BearerToken??"").Trim();if(BearerToken.Length>8192||BearerToken.Any(char.IsControl))throw new ArgumentException("Use one bearer token of at most 8,192 characters."); }
    public void Save() { Validate();CredentialStore.Save("craft-connection",JsonSerializer.Serialize(this)); }
    public static CraftConnection Load() { var value=CredentialStore.Read("craft-connection");if(value==null)throw new InvalidOperationException("Save a Craft API connection first.");var connection=JsonSerializer.Deserialize<CraftConnection>(value)??throw new InvalidDataException("The saved Craft connection is invalid.");_=connection.BaseUri;return connection; }
}

/// <summary>Reconciles only objects bearing this board's ownership metadata. All other remote objects are preserved.</summary>
public sealed class CraftClient
{
    private readonly CraftConnection connection;
    private readonly HttpClient client;
    public CraftClient(CraftConnection connection,HttpClient? client=null) { connection.Validate();this.connection=new(){Endpoint=connection.BaseUri.AbsoluteUri,BearerToken=connection.BearerToken};this.client=client??ServiceHttp.NetworkClient; }
    public async Task<int> SendAsync(Board board,string whiteboardId,CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if(!CraftConnection.ValidIdentifier(whiteboardId))throw new ArgumentException("Enter the block ID of one target Craft whiteboard.");
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);timeout.CancelAfter(TimeSpan.FromSeconds(90));var ct=timeout.Token;
        try { return await ReconcileAsync(board,whiteboardId,ct); }
        catch(OperationCanceledException) when(!cancellationToken.IsCancellationRequested) { throw new TimeoutException("Craft send timed out. Some changes may already have been accepted; Send again to reconcile. Your local drawing is unchanged."); }
        catch(JsonException ex) { throw new InvalidDataException("Craft returned unreadable JSON. Send again to reconcile accepted changes.",ex); }
        catch(HttpRequestException) { throw new IOException("Craft could not be reached. Send again to reconcile any accepted changes. Your local drawing is unchanged."); }
    }
    private async Task<int> ReconcileAsync(Board board,string whiteboardId,CancellationToken ct)
    {
        var desired=CraftExchange.VectorElements(board).Select(x=>JsonSerializer.SerializeToNode(x)!.AsObject()).ToArray();var boardID=board.Id.ToString().ToUpperInvariant();var prefix="karim-"+boardID.ToLowerInvariant()+"-";var path="whiteboards/"+whiteboardId+"/elements";
        var initial=await Request(HttpMethod.Get,path,null,ct);var remote=ReadElements(initial);var byId=remote.ToDictionary(x=>StringValue(x["id"])!);
        var wanted=desired.Select(x=>x["id"]!.GetValue<string>()).ToHashSet();
        bool Owned(JsonObject x)=>x["customData"] is JsonObject data&&StringValue(data["boardID"])==boardID&&StringValue(data["app"])=="Karim Eldamaty";
        foreach(var id in wanted) if(byId.TryGetValue(id,out var previous)&&!Owned(previous))throw new InvalidOperationException("An imported ID belongs to another Craft object. Choose a separate whiteboard; this object will not be overwritten.");
        var add=desired.Where(x=>!byId.ContainsKey(x["id"]!.GetValue<string>())).ToArray();var update=desired.Where(x=>byId.ContainsKey(x["id"]!.GetValue<string>())).Select(x=> {var copy=x.DeepClone().AsObject();var previous=byId[x["id"]!.GetValue<string>()];copy["version"]=Math.Min(int.MaxValue-1,Math.Max(1,ReadVersion(previous)))+1;copy["versionNonce"]=Random.Shared.Next(1,int.MaxValue);return copy;}).ToArray();
        var remove=byId.Where(p=>p.Key.StartsWith(prefix,StringComparison.Ordinal)&&!wanted.Contains(p.Key)&&!Deleted(p.Value)&&Owned(p.Value)).Select(p=>p.Key).ToArray();
        foreach(var batch in add.Chunk(500))await Request(HttpMethod.Post,path,new{elements=batch},ct);
        var initialize=add.Select(x=>{var copy=x.DeepClone().AsObject();copy["version"]=2;copy["versionNonce"]=Random.Shared.Next(1,int.MaxValue);return copy;});
        foreach(var batch in update.Concat(initialize).Chunk(500))await Request(HttpMethod.Put,path,new{elements=batch},ct);
        foreach(var batch in remove.Chunk(500))await Request(HttpMethod.Delete,path,new{elementIds=batch},ct);
        var final=ReadElements(await Request(HttpMethod.Get,path,null,ct)).Where(x=>!Deleted(x)).ToDictionary(x=>StringValue(x["id"])!);
        if(wanted.Any(id=>!final.ContainsKey(id))||remove.Any(final.ContainsKey))throw VerificationError();
        foreach(var value in desired)
        {
            var persisted=final[value["id"]!.GetValue<string>()];if(!Owned(persisted))throw VerificationError();
            foreach(var key in new[]{"type","x","y","width","height","angle","strokeColor","backgroundColor","strokeWidth","opacity","points","pressures","text"})if(value.ContainsKey(key)&&!Equivalent(value[key],persisted[key]))throw VerificationError();
        }
        return desired.Length;
    }
    private static InvalidOperationException VerificationError()=>new("Craft accepted changes but verification did not match all objects. Send again to reconcile; your local drawing is unchanged.");
    private static bool Equivalent(JsonNode? a,JsonNode? b)
    {
        if(a==null||b==null)return a==b;
        if(a is JsonArray aa&&b is JsonArray bb)return aa.Count==bb.Count&&aa.Zip(bb).All(p=>Equivalent(p.First,p.Second));
        if(a is JsonValue av&&b is JsonValue bv){if(double.TryParse(av.ToJsonString(),System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var ad)&&double.TryParse(bv.ToJsonString(),System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var bd))return Math.Abs(ad-bd)<=1e-7*Math.Max(1,Math.Abs(ad));}
        return JsonNode.DeepEquals(a,b);
    }
    private static string? StringValue(JsonNode? node)=>node is JsonValue value&&value.TryGetValue<string>(out var text)?text:null;
    private static int ReadVersion(JsonObject element)=>element["version"]==null?1:element["version"] is JsonValue value&&value.TryGetValue<int>(out var version)&&version>=0?version:throw new InvalidDataException("Craft returned an invalid object version. No objects were changed.");
    private static bool Deleted(JsonObject element)=>element["isDeleted"]==null?false:element["isDeleted"] is JsonValue value&&value.TryGetValue<bool>(out var deleted)?deleted:throw new InvalidDataException("Craft returned an invalid deletion flag.");
    private static JsonObject[] ReadElements(JsonObject obj)
    {
        if(obj["elements"] is not JsonArray values)throw new InvalidDataException("Craft returned an unexpected whiteboard response.");
        var elements=values.Select(x=>x as JsonObject??throw new InvalidDataException("Craft returned an unexpected element.")).ToArray();
        var ids=elements.Select(x=>StringValue(x["id"])).ToArray();
        if(ids.Any(x=>string.IsNullOrWhiteSpace(x)||x.Length>512)||ids.Distinct().Count()!=ids.Length)throw new InvalidDataException("Craft returned missing or duplicate object IDs. Send stopped to preserve remote objects.");
        foreach(var element in elements)_=Deleted(element);
        return elements;
    }
    private async Task<JsonObject> Request(HttpMethod method,string path,object? body,CancellationToken ct)
    {
        using var request=new HttpRequestMessage(method,new Uri(connection.BaseUri.AbsoluteUri+"/"+path));request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if(connection.BearerToken.Length>0)request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",connection.BearerToken);
        if(body!=null)request.Content=new StringContent(JsonSerializer.Serialize(body),Encoding.UTF8,"application/json");
        using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,ct);
        if(!response.IsSuccessStatusCode)throw new InvalidOperationException((int)response.StatusCode is 401 or 403?"Craft rejected this connection. Check its document scope and access settings.":(int)response.StatusCode==404?"The chosen Craft whiteboard could not be found in this connection's scope.":"Craft returned HTTP "+(int)response.StatusCode+". Send again to reconcile accepted changes.");
        var text=await ServiceHttp.ReadBoundedAsync(response,16000000,ct);return text.Length==0?new():JsonNode.Parse(text) as JsonObject??throw new InvalidDataException("Craft returned an unexpected response.");
    }
}
