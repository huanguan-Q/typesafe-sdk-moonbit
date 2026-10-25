///|
/// JS-backend transport built on the host `fetch()` (browser, Node 18+,
/// Deno, workers). Check/build this package with `--target js`.
///
/// Bindings are callback-based: `fetch` returns a promise, so SDK calls
/// complete asynchronously. `evaluate_async_with_retries` drives the full
/// verified retry policy (including HTTP-date Retry-After) through the
/// host `setTimeout` and `Date` clock.
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
extern "js" fn js_set_timeout(ms : Int, wake : () -> Unit) -> Unit =
  #| (ms, wake) => setTimeout(wake, ms)

///|
extern "js" fn js_now_secs() -> Int =
  #| () => Math.floor(Date.now() / 1000)

///|
/// An AsyncTransport that performs each call through the host `fetch`.
pub fn fetch_transport(config : @sdk.ClientConfig) -> @sdk.AsyncTransport {
  {
    deliver: fn(
      request : @sdk.HttpRequest,
      on_result : (Result[@sdk.HttpResponse, @sdk.TransportError]) -> Unit,
    ) -> Unit {
      let auth = match request.headers.get("authorization") {
        Some(value) => value
        None => "Bearer " + config.api_key
      }
      js_fetch_post(
        request.url,
        request.body,
        auth,
        fn(status : Int, retry_after : String, body : String) -> Unit {
          let headers : Map[String, String] = Map([])
          if retry_after != "" {
            headers.set("retry-after", retry_after)
          }
          on_result(Ok({ status, headers, body, }))
        },
        fn(message : String) -> Unit {
          on_result(Err(@sdk.TransportError::NetworkFailure(message)))
        },
      )
    },
  }
}

///|
/// One asynchronous System One call through the host `fetch`, with no
/// retries. `on_done` receives the decoded response or a classified
/// error, including the Retry-After value on 429.
pub fn evaluate_async(
  config : @sdk.ClientConfig,
  request : @sdk.SystemOneRequest,
  on_done : (Result[@sdk.SystemOneResponse, @sdk.SdkError]) -> Unit,
) -> Unit {
  let transport = fetch_transport(config)
  (transport.deliver)(@sdk.build_http_request(config, request), fn(result) {
    match result {
      Ok(response) => on_done(@sdk.classify_response(response, js_now_secs()))
      Err(@sdk.TransportError::NetworkFailure(message)) =>
        on_done(Err(@sdk.SdkError::Network(message)))
    }
  })
}

///|
/// Asynchronous System One call with the full verified retry policy:
/// Retry-After (delay-seconds or HTTP-date) is honored exactly, otherwise
/// exponential backoff capped at `max_delay_ms`; retries are scheduled
/// with the host `setTimeout` and the clock comes from `Date`.
pub fn evaluate_async_with_retries(
  config : @sdk.ClientConfig,
  request : @sdk.SystemOneRequest,
  on_done : (Result[@sdk.SystemOneResponse, @sdk.SdkError]) -> Unit,
) -> Unit {
  @sdk.evaluate_with_retries_async(
    config,
    fetch_transport(config),
    request,
    fn(ms : Int, wake : () -> Unit) { js_set_timeout(ms, wake) },
    fn() { js_now_secs() },
    on_done,
  )
}
