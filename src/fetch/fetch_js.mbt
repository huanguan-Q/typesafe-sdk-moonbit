///|
/// JS-backend transport built on the host `fetch()` (browser, Node 18+,
/// Deno, workers). Check/build this package with `--target js`.
///
/// The binding is callback-based: `fetch` returns a promise, so the SDK call
/// completes asynchronously. Retries are not driven here in v0.1 — call
/// `evaluate_with_retries` from the root package with your own timer glue,
/// or wrap `evaluate_async`.
///
/// Security: shipping an API key to a browser exposes it to every user. In
/// production web apps, proxy requests through your backend and keep the
/// key server-side.
extern "js" fn js_fetch_post(
  url : String,
  body : String,
  auth : String,
  on_ok : (Int, String, String) -> Unit,
  on_err : (String) -> Unit,
) -> Unit =
  #| (url, body, auth, on_ok, on_err) => {
  #|   fetch(url, {
  #|     method: 'POST',
  #|     headers: { 'Content-Type': 'application/json', Authorization: auth },
  #|     body: body,
  #|   })
  #|     .then(async (r) => {
  #|       const retryAfter = r.headers.get('retry-after') || '';
  #|       on_ok(r.status, retryAfter, await r.text());
  #|     })
  #|     .catch((e) => on_err(String(e)));
  #| }

///|
/// One asynchronous System One call through the host `fetch`.
/// `on_done` receives the decoded response or a classified error,
/// including the Retry-After value on 429.
pub fn evaluate_async(
  config : @sdk.ClientConfig,
  request : @sdk.SystemOneRequest,
  on_done : (Result[@sdk.SystemOneResponse, @sdk.SdkError]) -> Unit,
) -> Unit {
  let body = @sdk.encode_request_to_string(request)
  js_fetch_post(
    config.base_url + "/v1/systemone",
    body,
    "Bearer " + config.api_key,
    fn(status : Int, retry_after : String, body : String) -> Unit {
      let headers : Map[String, String] = Map([])
      if retry_after != "" {
        headers.set("retry-after", retry_after)
      }
      on_done(@sdk.classify_response({ status, headers, body, }))
    },
    fn(message : String) -> Unit {
      on_done(Err(@sdk.SdkError::Network(message)))
    },
  )
}
