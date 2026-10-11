using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Net.Sockets;
using KarimEldamatyWindows;

var passes=new List<string>();
var assertions=0;
void Check(bool condition,string message){assertions++;if(!condition)throw new Exception("FAIL: "+message);}
async Task Test(string name,Func<Task> action){await action();passes.Add(name);Console.WriteLine("PASS "+name);}
async Task Throws<T>(Func<Task> action,string message) where T:Exception{assertions++;try{await action();}catch(T){return;}throw new Exception("FAIL no expected "+typeof(T).Name+": "+message);}
async Task<T> ExceptionFrom<T>(Func<Task> action) where T:Exception{assertions++;try{await action();}catch(T ex){return ex;}throw new Exception("FAIL no expected "+typeof(T).Name);}
HttpResponseMessage Response(string text,HttpStatusCode code=HttpStatusCode.OK)=>new(code){Content=new StringContent(text,Encoding.UTF8,"application/json")};

await Test("OpenAI Responses shape, store:false, text-only and deliberate PNG attachment",async()=>
{
    var count=0;var withImage=false;var handler=new Handler(async(request,ct)=>
    {
        count++;Check(request.RequestUri!.AbsoluteUri=="https://api.openai.com/v1/responses","fixed official endpoint");Check(request.Headers.Authorization?.ToString()=="Bearer test-key","API bearer present only on cloud");
        using var data=JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));var root=data.RootElement;Check(root.GetProperty("store").ValueKind==JsonValueKind.False,"store false");Check(root.GetProperty("model").GetString()=="gpt-4.1","Mac default kept");var content=root.GetProperty("input")[0].GetProperty("content");Check(content[0].GetProperty("type").GetString()=="input_text","text item");Check(content.GetArrayLength()==(withImage?2:1),"image only when explicitly passed");if(withImage)Check(content[1].GetProperty("image_url").GetString()!.StartsWith("data:image/png;base64,"),"inline PNG");
        return Response("{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Worked answer: 12 mm\"}]}]}");
    });var service=new AssistantService(new HttpClient(handler),()=>"test-key");Check(count==0,"no network until Send");var result=await service.SendAsync(new(){Backend=AIBackend.OpenAI},"Explain 12 mm",null,default);Check(result.Text=="Worked answer: 12 mm","Responses text parsed");withImage=true;await service.SendAsync(new(){Backend=AIBackend.OpenAI},"Read drawing",BoardExport.RenderPNG(new()),default);Check(count==2,"exactly deliberate requests");
});
await Test("Ollama fixed loopback, no auth and no cloud fallback",async()=>
{
    var calls=0;var handler=new Handler(async(request,ct)=>{calls++;Check(request.RequestUri!.AbsoluteUri=="http://127.0.0.1:11434/api/generate","fixed loopback");Check(request.Headers.Authorization==null,"no API key to local");using var data=JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));Check(!data.RootElement.GetProperty("stream").GetBoolean(),"non-stream JSON");return Response("{\"response\":\"Local engineering explanation\"}");});
    var service=new AssistantService(new HttpClient(handler),()=>"cloud-key");var settings=new AISettingsConfig{Backend=AIBackend.Auto,LocalModel="qwen3:4b"};var result=await service.SendAsync(settings,"Test",null,default);Check(result.Route.StartsWith("Local"),"Auto uses configured local");await Throws<InvalidOperationException>(()=>service.SendAsync(settings,"Test",BoardExport.RenderPNG(new()),default),"local image reject");Check(calls==1,"local image rejected before network");
    var failCalls=0;var fail=new AssistantService(new HttpClient(new Handler((_,_)=>{failCalls++;return Task.FromResult(Response("{}",HttpStatusCode.ServiceUnavailable));})),()=>"cloud-key");await Throws<InvalidOperationException>(()=>fail.SendAsync(settings,"Test",null,default),"local HTTP failure");Check(failCalls==1,"no fallback cloud request");
});
await Test("Assistant empty prompt, API auth, empty reply and cancellation errors",async()=>
{
    var calls=0;var service=new AssistantService(new HttpClient(new Handler((_,_)=>{calls++;return Task.FromResult(Response("{}"));})),()=>null);await Throws<ArgumentException>(()=>service.SendAsync(new()," ",null,default),"empty prompt");await Throws<InvalidOperationException>(()=>service.SendAsync(new(),"Question",null,default),"missing credential");Check(calls==0,"preflight no network");
    var empty=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(Response("{\"output\":[]}")))),()=>"test");await Throws<InvalidDataException>(()=>empty.SendAsync(new(),"Question",null,default),"no output");
    var auth=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(Response("{}",HttpStatusCode.Unauthorized)))),()=>"test");await Throws<InvalidOperationException>(()=>auth.SendAsync(new(),"Question",null,default),"HTTP auth");
    using var cancel=new CancellationTokenSource();var cancelled=new AssistantService(new HttpClient(new Handler(async(_,ct)=>{cancel.Cancel();await Task.Delay(1000,ct);return Response("{}");})),()=>"test");await Throws<OperationCanceledException>(()=>cancelled.SendAsync(new(),"Question",null,cancel.Token),"cancellation");
});
await Test("Craft geometry mappings and offline Notion HTML escaping",()=>
{
    var b=new Board{Id=Guid.Parse("dca8c9ce-8e3a-4e09-8d36-5bb054785ad4"),Title="</script><script>alert(1)</script>",PointsPerMM=4,ScaleDenominator=2,Elements=[new(){Kind="stroke",Points=[new(10,20,.2),new(30,40,.8)]},new(){Kind="dimension",Points=[new(0,0),new(40,0)]},new(){Kind="triangle",Points=[new(0,0),new(10,10)]},new(){Kind="text",Points=[new(30,50)],Text="12 Ω"}]};
    var values=CraftExchange.VectorElements(b);Check(values.Count==5,"dimension includes label");var ink=values.First(x=>Equals(x["type"],"freedraw"));var points=(double[][])ink["points"]!;Check(points[0][0]==0&&points[1][1]==20,"relative geometry");Check(((double[])ink["pressures"]!)[1]==.8,"pressure retained");Check(values.Any(x=>Equals(x.GetValueOrDefault("text"),"20 mm")),"calibrated dimension");var triangle=values.First(x=>x.GetValueOrDefault("polygon")is true);Check(((double[][])triangle["points"]!).Length==4,"closed triangle");
    Check(CraftExchange.NativeLink(b)=="karimboard://board/DCA8C9CE-8E3A-4E09-8D36-5BB054785AD4","Mac canonical UUID link");var html=NotionHTMLExport.Html(b,BoardExport.RenderPNG(b));Check(!html.Contains(b.Title),"title JSON escaped");Check(html.Contains("connect-src 'none'"),"offline HTML CSP");Check(html.Contains("karimboard-web-ink")&&html.Contains("validStroke"),"editable new ink export validation");return Task.CompletedTask;
});
await Test("Craft one-way ownership, unrelated-object preservation and verification",async()=>
{
    var board=new Board{Id=Guid.Parse("dca8c9ce-8e3a-4e09-8d36-5bb054785ad4"),Elements=[new(){Kind="line",Points=[new(10,10),new(80,40)]}]};var id=board.Id.ToString().ToUpperInvariant();
    JsonObject owned(string element)=>new(){["id"]=element,["version"]=1,["isDeleted"]=false,["customData"]=new JsonObject{["app"]="Karim Eldamaty",["boardID"]=id}};
    var stale="karim-"+id.ToLowerInvariant()+"-old";var other="someone-elses-object";var state=new Dictionary<string,JsonObject>{{stale,owned(stale)},{other,new(){["id"]=other,["type"]="rectangle",["isDeleted"]=false}}};var mutations=0;
    var handler=new Handler(async(request,ct)=>
    {
        Check(request.RequestUri!.AbsoluteUri=="https://connect.craft.do/link/test/api/v1/whiteboards/target/elements","scoped fixed Craft URL");
        if(request.Method==HttpMethod.Get)return Response(new JsonObject{["elements"]=new JsonArray(state.Values.Select(x=>x.DeepClone()).ToArray())}.ToJsonString());mutations++;var body=JsonNode.Parse(await request.Content!.ReadAsStringAsync(ct))!.AsObject();
        if(request.Method==HttpMethod.Delete){foreach(var key in body["elementIds"]!.AsArray())state.Remove(key!.GetValue<string>());}else foreach(var e in body["elements"]!.AsArray()){var copy=e!.DeepClone().AsObject();state[copy["id"]!.GetValue<string>()]=copy;}return Response("{}");
    });var client=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(handler));var count=await client.SendAsync(board,"target",default);Check(count==1,"one desired object verified");Check(state.ContainsKey(other)&&!state.ContainsKey(stale),"unrelated kept, owned stale removed");Check(mutations==3,"POST initialized with PUT, only owned DELETE");
    var desired=CraftExchange.VectorElements(board)[0]["id"]!.ToString()!;state[desired]["customData"]=new JsonObject{["app"]="Another app",["boardID"]=id};var before=mutations;await Throws<InvalidOperationException>(()=>client.SendAsync(board,"target",default),"ownership collision");Check(mutations==before,"collision stops before mutation");
});
await Test("Craft rejects unsafe connection and incomplete remote geometry",async()=>
{
    foreach(var value in new[]{"http://connect.craft.do/link/a/api/v1","https://evil.example/link/a/api/v1","https://connect.craft.do/link/a/api/v1?token=a","https://connect.craft.do/link/a/api/v1/extra"}){try{_=new CraftConnection{Endpoint=value}.BaseUri;throw new Exception("accepted unsafe connection");}catch(ArgumentException){}}
    var board=new Board{Elements=[new(){Kind="line",Points=[new(1,2),new(3,4)]}]};var count=0;var client=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(new Handler((r,c)=>{if(r.Method==HttpMethod.Get){count++;return Task.FromResult(Response("{\"elements\":[]}"));}return Task.FromResult(Response("{}"));})));await Throws<InvalidOperationException>(()=>client.SendAsync(board,"target",default),"verification mismatch");Check(count==2,"verifies GET after mutations");
});
await Test("Responses malformed structures, refusals and incomplete-answer review",async()=>
{
    foreach(var payload in new[]{"[]","null","{","{\"output\":[1,null,{\"content\":[false,{\"type\":5},{\"type\":\"output_text\",\"text\":2}]}]}","{\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"   \"}]}]}"})
    {var service=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(Response(payload)))),()=>"test-key");await Throws<InvalidDataException>(()=>service.SendAsync(new(),"Question",null,default),"malformed or empty output");}
    var service2=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(Response("{\"status\":\"incomplete\",\"output\":[null,{\"content\":[{\"type\":\"refusal\",\"refusal\":\"Unable to answer this prompt.\"},{\"type\":\"output_text\",\"text\":\"Use SI units.\"}]}]}")))),()=>"test-key");
    var reply=await service2.SendAsync(new(),"Question",null,default);Check(reply.Text.Contains("Unable to answer")&&reply.Text.Contains("Use SI units."),"refusal and text retained");Check(reply.Text.Contains("cut short"),"incomplete answer explicitly labelled");
});
await Test("AI preflight rejects invalid settings, images, headers and prior cancellation",async()=>
{
    var count=0;var keyReads=0;var service=new AssistantService(new HttpClient(new Handler((_,_)=>{count++;return Task.FromResult(Response("{}"));})),()=>{keyReads++;return "test-key";});
    foreach(var settings in new AISettingsConfig[]{new(){Backend=(AIBackend)88},new(){Model=null!},new(){Model=new string('a',121)},new(){LocalModel="bad\nmodel"}})await Throws<ArgumentException>(()=>service.SendAsync(settings,"Question",null,default),"settings rejected");
    await Throws<ArgumentException>(()=>service.SendAsync(new(),new string('a',40001),null,default),"prompt bound");await Throws<ArgumentException>(()=>service.SendAsync(new(),"Question",new byte[]{1,2,3},default),"invalid PNG");
    var tooWide=BoardExport.RenderPNG(new());System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(tooWide.AsSpan(16,4),4097);await Throws<ArgumentException>(()=>service.SendAsync(new(),"Question",tooWide,default),"oversized PNG dimensions");
    using var stopped=new CancellationTokenSource();stopped.Cancel();await Throws<OperationCanceledException>(()=>service.SendAsync(new(),"Question",null,stopped.Token),"cancel before Send");Check(count==0&&keyReads==0,"invalid requests neither read keys nor send HTTP");
    var badKey=new AssistantService(new HttpClient(new Handler((_,_)=>{count++;return Task.FromResult(Response("{}"));})),()=>"secret-test-value\r\nheader");var error=await ExceptionFrom<InvalidOperationException>(()=>badKey.SendAsync(new(),"Question",null,default));Check(!error.Message.Contains("secret-test-value"),"credential never appears in invalid-header message");Check(count==0,"invalid credential no network");
});
await Test("AI HTTP failures, bounded bodies and cancellation versus timeout",async()=>
{
    foreach(var status in new[]{HttpStatusCode.Unauthorized,HttpStatusCode.Forbidden,HttpStatusCode.TooManyRequests,HttpStatusCode.InternalServerError,HttpStatusCode.TemporaryRedirect})
    {var calls=0;var service=new AssistantService(new HttpClient(new Handler((_,_)=>{calls++;return Task.FromResult(Response("secret-test-server-body",status));})),()=>"test-key");var error=await ExceptionFrom<InvalidOperationException>(()=>service.SendAsync(new(),"Question",null,default));Check(!error.Message.Contains("secret-test-server-body"),"server body excluded from user error");Check(calls==1,"HTTP failures no retry or route fallback");}
    foreach(var chunked in new[]{false,true})
    {var content=chunked?(HttpContent)new UnknownLengthContent(new byte[4000001]):new ByteArrayContent(new byte[4000001]);var service=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=content}))),()=>"test-key");await Throws<InvalidDataException>(()=>service.SendAsync(new(),"Question",null,default),"large ContentLength or chunked body");}
    var timeout=new AssistantService(new HttpClient(new Handler((_,_)=>throw new TaskCanceledException("simulated transport timeout"))),()=>"test-key");await Throws<TimeoutException>(()=>timeout.SendAsync(new(),"Question",null,default),"transport cancellation without caller cancellation is timeout");
    var unreachable=new AssistantService(new HttpClient(new Handler((_,_)=>throw new HttpRequestException("private-server-token"))),()=>"test-key");var network=await ExceptionFrom<IOException>(()=>unreachable.SendAsync(new(),"Question",null,default));Check(!network.Message.Contains("private-server-token"),"transport detail omitted");
});
await Test("Ollama model discovery is manual, bounded, authenticated nowhere and safely parsed",async()=>
{
    var count=0;var keyReads=0;var service=new AssistantService(new HttpClient(new Handler((request,ct)=>{count++;Check(request.RequestUri!.AbsoluteUri=="http://127.0.0.1:11434/api/tags"&&request.Method==HttpMethod.Get,"loopback discovery GET");Check(request.Headers.Authorization==null,"discovery has no bearer");return Task.FromResult(Response("{\"models\":[null,5,{}, {\"name\":5},{\"name\":\"qwen3:4b\"},{\"name\":\" qwen3:4b \"},{\"name\":\"llama3:8b\"},{\"name\":\"bad\\nmodel\"}]}"));})),()=>{keyReads++;throw new Exception("local route must not read cloud key");});Check(count==0,"constructing service does not discover models");var models=await service.ListLocalModelsAsync(default);Check(models.SequenceEqual(new[]{"llama3:8b","qwen3:4b"}),"valid distinct sorted names");Check(keyReads==0,"manual local discovery does not touch cloud credential");
    var local=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(Response("{\"response\":\"Local only\"}")))),()=>throw new Exception("local cloud key access"));await local.SendAsync(new(){Backend=AIBackend.Auto,LocalModel="qwen3:4b"},"Question",null,default);
    foreach(var payload in new[]{"null","[]","{}","{\"models\":3}","{"}){var invalid=new AssistantService(new HttpClient(new Handler((_,_)=>Task.FromResult(Response(payload)))));await Throws<InvalidDataException>(()=>invalid.ListLocalModelsAsync(default),"invalid models payload");}
    var timed=new AssistantService(new HttpClient(new Handler((_,_)=>throw new TaskCanceledException())));await Throws<TimeoutException>(()=>timed.ListLocalModelsAsync(default),"model refresh timeout");
    using var stopped=new CancellationTokenSource();stopped.Cancel();await Throws<OperationCanceledException>(()=>service.ListLocalModelsAsync(stopped.Token),"cancelled discovery");Check(count==1,"cancelled discovery no request");
});
await Test("DPAPI names and bounds, isolated settings and no secrets in exports",async()=>
{
    var directory=Path.Combine(Path.GetTempPath(),"Karim-Service-Tests-"+Guid.NewGuid().ToString("N"));App.TestDataDirectory=directory;
    try
    {
        foreach(var name in new[]{"","../secret","a/b","a\\b","a:b","file.dpapi","key\n",new string('a',81),"κλειδί"}){await Throws<ArgumentException>(()=>Task.Run(()=>CredentialStore.Save(name,"fake-test-value")),"invalid credential name");await Throws<ArgumentException>(()=>Task.Run(()=>CredentialStore.Read(name)),"invalid read name");await Throws<ArgumentException>(()=>Task.Run(()=>CredentialStore.Delete(name)),"invalid delete name");}
        await Throws<ArgumentException>(()=>Task.Run(()=>CredentialStore.Save("test-key","")),"empty credential");await Throws<ArgumentException>(()=>Task.Run(()=>CredentialStore.Save("test-key",new string('Ω',33000))),"UTF8 size bound");Check(!Directory.Exists(directory),"invalid credentials write no files");
        if(OperatingSystem.IsWindows()){CredentialStore.Save("test-key","fake-test-value");Check(CredentialStore.Read("test-key")=="fake-test-value","isolated Windows DPAPI roundtrip");Check(!Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(directory,"Credentials","test-key.dpapi"))).Contains("fake-test-value"),"ciphertext hides fake secret");CredentialStore.Delete("test-key");}else await Throws<PlatformNotSupportedException>(()=>Task.Run(()=>CredentialStore.Save("test-key","fake-test-value")),"non-Windows DPAPI refuses plaintext fallback");
        Check(CredentialStore.Read("absent")==null,"absent credential no decrypt");new AISettingsConfig{Backend=AIBackend.Local,LocalModel=" qwen3:4b "}.Save();var loaded=AISettingsConfig.Load();Check(loaded.EffectiveBackend==AIBackend.Local&&loaded.LocalModel=="qwen3:4b","settings trimmed and isolated");var settingsFile=Path.Combine(directory,"assistant.json");Check(File.Exists(settingsFile),"settings in temporary directory");File.WriteAllText(settingsFile,"{\"Backend\":99,\"Model\":null}");Check(AISettingsConfig.Load().Model=="gpt-4.1","bad settings restore safe defaults");
        Directory.CreateDirectory(Path.Combine(directory,"Credentials"));File.WriteAllBytes(Path.Combine(directory,"Credentials","oversize.dpapi"),new byte[131073]);await Throws<InvalidDataException>(()=>Task.Run(()=>CredentialStore.Read("oversize")),"oversized ciphertext rejected before native decrypt");
        var board=new Board();Check(!JsonSerializer.Serialize(CraftExchange.Scene(board)).Contains("fake-test-value")&&!NotionHTMLExport.Html(board,BoardExport.RenderPNG(board)).Contains("fake-test-value"),"board exports contain no credentials");
    }
    finally{App.TestDataDirectory=null;if(Directory.Exists(directory))Directory.Delete(directory,true);}
});
await Test("Craft rejects ambiguous IDs and malformed flags before mutation",async()=>
{
    foreach(var payload in new[]{"[]","{","{}","{\"elements\":[null]}","{\"elements\":[{\"id\":5}]}","{\"elements\":[{\"id\":\"same\"},{\"id\":\"same\"}]}","{\"elements\":[{\"id\":\"a\",\"isDeleted\":\"false\"}]}"})
    {var mutations=0;var client=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(new Handler((request,_)=>{if(request.Method!=HttpMethod.Get)mutations++;return Task.FromResult(Response(payload));})));await Throws<InvalidDataException>(()=>client.SendAsync(new(),"target",default),"invalid remote scene");Check(mutations==0,"malformed remote scene never mutated");}
    var requests=0;var basic=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(new Handler((_,_)=>{requests++;return Task.FromResult(Response("{}"));})));await Throws<InvalidOperationException>(()=>basic.SendAsync(new(){Elements=[new(){Kind="image",Points=[new(1,2),new(3,4)]}]},"target",default),"complex images rejected before HTTP");await Throws<ArgumentException>(()=>basic.SendAsync(new(),"../other",default),"unsafe target");using var stop=new CancellationTokenSource();stop.Cancel();await Throws<OperationCanceledException>(()=>basic.SendAsync(new(),"target",stop.Token),"cancel before craft");Check(requests==0,"all Craft preflight failures before HTTP");
});
await Test("Craft preserves unrelated prefixed objects and uses maximum 500-item batches",async()=>
{
    var board=new Board{Elements=Enumerable.Range(0,1001).Select(i=>new DrawingElement{Kind="line",Points=[new(i,0),new(i+1,10)]}).ToList()};var fakeID="karim-"+board.Id.ToString().ToLowerInvariant()+"-other-app";var state=new Dictionary<string,JsonObject>{{fakeID,new(){["id"]=fakeID,["customData"]=new JsonObject{["app"]=5,["boardID"]=board.Id.ToString().ToUpperInvariant()}}}};var posts=0;var puts=0;var deletes=0;
    var client=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1",BearerToken="fake-bearer"},new HttpClient(new Handler(async(request,ct)=>{Check(request.Headers.Authorization?.Parameter=="fake-bearer","Craft bearer only configured endpoint");if(request.Method==HttpMethod.Get)return Response(new JsonObject{["elements"]=new JsonArray(state.Values.Select(x=>x.DeepClone()).ToArray())}.ToJsonString());var body=JsonNode.Parse(await request.Content!.ReadAsStringAsync(ct))!.AsObject();if(request.Method==HttpMethod.Delete){deletes++;return Response("{}");}var elements=body["elements"]!.AsArray();Check(elements.Count is >0 and <=500,"bounded mutation batch");if(request.Method==HttpMethod.Post)posts++;if(request.Method==HttpMethod.Put)puts++;foreach(var value in elements){var e=value!.DeepClone().AsObject();state[e["id"]!.GetValue<string>()]=e;}return Response("{}");})));Check(await client.SendAsync(board,"target",default)==1001,"all geometry verified across batches");Check(posts==3&&puts==3&&deletes==0,"1001 additions use three POST and initialization PUT batches");Check(state.ContainsKey(fakeID),"unrelated object preserved despite matching ID prefix");
});
await Test("Craft connection snapshots, transport failures and verified geometry mismatch",async()=>
{
    foreach(var endpoint in new[]{"https://user@connect.craft.do/link/a/api/v1","https://connect.craft.do:444/link/a/api/v1","https://connect.craft.do/link/a/api/v1#x","https://connect.craft.do/link/%61/api/v1","https://connect.craft.do/link/a/../api/v1"})await Throws<ArgumentException>(()=>Task.Run(()=>_=new CraftConnection{Endpoint=endpoint}.BaseUri),"unsafe endpoint");
    await Throws<ArgumentException>(()=>Task.Run(()=>_=new CraftClient(new(){Endpoint="https://connect.craft.do/link/a/api/v1",BearerToken="fake\r\nheader"})),"malformed bearer");
    var connection=new CraftConnection{Endpoint="https://connect.craft.do/link/original/api/v1"};var gets=0;var client=new CraftClient(connection,new HttpClient(new Handler((request,_)=>{gets++;Check(request.RequestUri!.AbsolutePath.StartsWith("/link/original/"),"connection snapshot fixed for operation");return Task.FromResult(Response("{\"elements\":[]}"));})));connection.Endpoint="https://connect.craft.do/link/changed/api/v1";await client.SendAsync(new(),"target",default);Check(gets==2,"empty scene verified without mutation");
    var timeout=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(new Handler((_,_)=>throw new TaskCanceledException())));await Throws<TimeoutException>(()=>timeout.SendAsync(new(),"target",default),"Craft timeout review");
    var failed=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(new Handler((_,_)=>throw new HttpRequestException("secret-server-value"))));var error=await ExceptionFrom<IOException>(()=>failed.SendAsync(new(),"target",default));Check(!error.Message.Contains("secret-server-value"),"Craft network error excludes private details");
    var board=new Board{Elements=[new(){Kind="line",Points=[new(1,2),new(3,4)]}]};var remote=new JsonArray();var altered=new CraftClient(new(){Endpoint="https://connect.craft.do/link/test/api/v1"},new HttpClient(new Handler(async(request,ct)=>{if(request.Method==HttpMethod.Get)return Response(new JsonObject{["elements"]=remote.DeepClone()}.ToJsonString());var body=JsonNode.Parse(await request.Content!.ReadAsStringAsync(ct))!;remote=(JsonArray)body["elements"]!.DeepClone();remote[0]!["x"]=999;return Response("{}");})));await Throws<InvalidOperationException>(()=>altered.SendAsync(board,"target",default),"accepted mismatching geometry not falsely verified");
});
await Test("Default loopback HTTP client never follows redirects",async()=>
{
    var server=new TcpListener(IPAddress.Loopback,0);server.Start();var redirectTarget=new TcpListener(IPAddress.Loopback,0);redirectTarget.Start();
    try
    {
        var sourcePort=((IPEndPoint)server.LocalEndpoint).Port;var targetPort=((IPEndPoint)redirectTarget.LocalEndpoint).Port;
        var reply=Task.Run(async()=>{using var socket=await server.AcceptTcpClientAsync();await using var stream=socket.GetStream();var request=new byte[4096];await stream.ReadAsync(request);var bytes=Encoding.ASCII.GetBytes("HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:"+targetPort+"/redirected\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");await stream.WriteAsync(bytes);});
        using var limit=new CancellationTokenSource(TimeSpan.FromSeconds(2));using var response=await ServiceHttp.LoopbackClient.GetAsync("http://127.0.0.1:"+sourcePort+"/local",limit.Token);await reply;Check(response.StatusCode==HttpStatusCode.TemporaryRedirect,"redirect returned to caller");Check(!redirectTarget.Pending(),"no request to redirected endpoint");
    }
    finally{server.Stop();redirectTarget.Stop();}
});
var report=new{status="passed",tests=passes.Count,assertions,cases=passes,scope="Production assistant HTTP, PNG validation, DPAPI preflight/settings isolation, Craft client/export and Notion HTML linked into a portable harness with model/geometry/render doubles. One real loopback HTTP redirect test. No live cloud requests. Native DPAPI roundtrip is conditional on Windows; WPF/OCR/math/physical pen are covered separately."};File.WriteAllText(Path.Combine(AppContext.BaseDirectory,"../../..","test-results.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("Passed "+passes.Count+" service cases and "+assertions+" assertions.");
sealed class Handler(Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> action):HttpMessageHandler{protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct)=>action(request,ct);}
sealed class UnknownLengthContent(byte[] bytes):HttpContent
{
    protected override bool TryComputeLength(out long length){length=0;return false;}
    protected override Task SerializeToStreamAsync(Stream stream,TransportContext? context)=>stream.WriteAsync(bytes).AsTask();
    protected override Task<Stream> CreateContentReadStreamAsync()=>Task.FromResult<Stream>(new MemoryStream(bytes));
}
