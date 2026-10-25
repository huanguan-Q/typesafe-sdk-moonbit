///|
/// Client orchestration: build the HTTP call, classify the response, and
/// drive retries through the verified policy in `retry.mbt`. Both a
/// blocking and a callback-based asynchronous entry point are provided.

///|
/// Client configuration. Keep `api_key` server-side in production web apps;
/// shipping it to a browser exposes it to users.
pub(all) struct ClientConfig {
  api_key : String
  model : String
  base_url : String
  retry : RetryPolicy
} derive(Debug)

///|
pub extend ClientConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Create a config with defaults: `jev-latest`, `https://api.typesafe.ai`,
/// and the default retry policy.
pub fn ClientConfig::make(
  api_key~ : String,
  model? : String = "jev-latest",
  base_url? : String = "https://api.typesafe.ai",
  retry? : RetryPolicy = RetryPolicy::defaults(),
) -> ClientConfig {
  { api_key, model, base_url, retry, }
}

///|
/// Whether an SdkError is transient and worth retrying: network failures,
/// 429 rate limits, and 5xx server errors. Validation and decode errors are
/// not retryable.
pub fn is_retryable(err : SdkError) -> Bool {
  match err {
    Network(_) => true
    RateLimited(_) => true
    Server(_, _) => true
    InvalidRequest(_, _) => false
    Decode(_) => false
  }
}

///|
fn retry_after_secs_of(err : SdkError) -> Int {
  match err {
    RateLimited(Some(secs)) => secs
    _ => -1
  }
}

///|
/// Classify an HTTP response into a decoded SystemOneResponse or an
/// SdkError: 200 decodes, 429 extracts Retry-After (seconds or HTTP-date,
/// resolved against `now_secs`), 5xx is retryable, other statuses are
/// invalid requests.
pub fn classify_response(
  response : HttpResponse,
  now_secs : Int,
) -> Result[SystemOneResponse, SdkError] {
  if response.status == 200 {
    decode_response(response.body)
  } else if response.status == 429 {
    Err(
      RateLimited(
        parse_retry_after(response.headers.get("retry-after"), now_secs),
      ),
    )
  } else if response.status >= 500 {
    Err(Server(response.status, response.body))
  } else {
    Err(InvalidRequest(response.status, response.body))
  }
}

///|
/// Build the outbound HTTP request for a System One call: bearer auth,
/// JSON content type, and the TypeSafe-Danger-Zone-Images header whenever
/// the request carries image assets.
pub fn build_http_request(
  config : ClientConfig,
  request : SystemOneRequest,
) -> HttpRequest {
  let headers : Map[String, String] = Map([
    ("authorization", "Bearer " + config.api_key),
    ("content-type", "application/json"),
  ])
  if request.assets.length() > 0 {
    headers.set("typesafe-danger-zone-images", "true")
  }
  {
    url: config.base_url + "/v1/systemone",
    http_method: "POST",
    headers,
    body: encode_request_to_string(request),
  }
}

///|
/// Perform exactly one evaluate call through a blocking transport.
pub fn evaluate_once(
  config : ClientConfig,
  transport : Transport,
  request : SystemOneRequest,
  now_secs : () -> Int,
) -> Result[SystemOneResponse, SdkError] {
  let http_request = build_http_request(config, request)
  match (transport.deliver)(http_request) {
    Err(NetworkFailure(message)) => Err(Network(message))
    Ok(response) => classify_response(response, now_secs())
  }
}

///|
/// Evaluate with retries over a blocking transport. `sleep_ms` and
/// `now_secs` are injected so tests run with zero waiting, a fixed clock,
/// and full observability; a real app passes its own timer and clock.
/// Retries follow the verified policy: a Retry-After directive (seconds or
/// HTTP-date) is honored exactly, otherwise exponential backoff capped at
/// `max_delay_ms`.
pub fn evaluate_with_retries(
  config : ClientConfig,
  transport : Transport,
  request : SystemOneRequest,
  sleep_ms : (Int) -> Unit,
  now_secs : () -> Int,
) -> Result[SystemOneResponse, SdkError] {
  let http_request = build_http_request(config, request)
  let mut attempts_done = 0
  let mut last : Result[SystemOneResponse, SdkError] = match
    (transport.deliver)(http_request) {
    Err(NetworkFailure(message)) => Err(Network(message))
    Ok(response) => classify_response(response, now_secs())
  }
  while should_retry(attempts_done, config.retry.max_retries) {
    match last {
      Ok(_) => break
      Err(err) =>
        if is_retryable(err) {
          sleep_ms(
            delay_ms(
              config.retry.base_delay_ms,
              config.retry.max_delay_ms,
              attempts_done,
              retry_after_secs_of(err),
            ),
          )
          attempts_done = attempts_done + 1
          last = match (transport.deliver)(http_request) {
            Err(NetworkFailure(message)) => Err(Network(message))
            Ok(response) => classify_response(response, now_secs())
          }
        } else {
          break
        }
    }
  }
  last
}

///|
fn evaluate_attempt_async(
  config : ClientConfig,
  http_request : HttpRequest,
  transport : AsyncTransport,
  sleep_async : (Int, () -> Unit) -> Unit,
  now_secs : () -> Int,
  attempts_done : Int,
  on_done : (Result[SystemOneResponse, SdkError]) -> Unit,
) -> Unit {
  (transport.deliver)(http_request, fn(response) {
    let outcome : Result[SystemOneResponse, SdkError] = match response {
      Ok(resp) => classify_response(resp, now_secs())
      Err(NetworkFailure(message)) => Err(Network(message))
    }
    match outcome {
      Ok(_) => on_done(outcome)
      Err(err) =>
        if should_retry(attempts_done, config.retry.max_retries) &&
          is_retryable(err) {
          sleep_async(
            delay_ms(
              config.retry.base_delay_ms,
              config.retry.max_delay_ms,
              attempts_done,
              retry_after_secs_of(err),
            ),
            fn() {
              evaluate_attempt_async(
                config,
                http_request,
                transport,
                sleep_async,
                now_secs,
                attempts_done + 1,
                on_done,
              )
            },
          )
        } else {
          on_done(outcome)
        }
    }
  })
}

///|
/// Evaluate with retries over an asynchronous transport. Completion is
/// delivered to `on_done`; `sleep_async(ms, wake)` schedules the retry
/// delay (tests pass an immediate scheduler); `now_secs` resolves
/// HTTP-date Retry-After headers. The retry policy is the same verified
/// core as the blocking path.
pub fn evaluate_with_retries_async(
  config : ClientConfig,
  transport : AsyncTransport,
  request : SystemOneRequest,
  sleep_async : (Int, () -> Unit) -> Unit,
  now_secs : () -> Int,
  on_done : (Result[SystemOneResponse, SdkError]) -> Unit,
) -> Unit {
  evaluate_attempt_async(
    config,
    build_http_request(config, request),
    transport,
    sleep_async,
    now_secs,
    0,
    on_done,
  )
}
