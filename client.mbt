///|
/// Client orchestration: build the HTTP call, classify the response, and
/// drive retries through the verified policy in `retry.mbt`.

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
    _ => 0
  }
}

///|
/// Classify an HTTP response into a decoded SystemOneResponse or an SdkError:
/// 200 decodes, 429 extracts Retry-After, 5xx is retryable, other statuses
/// are invalid requests.
pub fn classify_response(
  response : HttpResponse,
) -> Result[SystemOneResponse, SdkError] {
  if response.status == 200 {
    decode_response(response.body)
  } else if response.status == 429 {
    Err(RateLimited(parse_retry_after(response.headers.get("retry-after"))))
  } else if response.status >= 500 {
    Err(Server(response.status, response.body))
  } else {
    Err(InvalidRequest(response.status, response.body))
  }
}

///|
/// Perform exactly one evaluate call through the transport. No retries.
pub fn evaluate_once(
  config : ClientConfig,
  transport : Transport,
  request : SystemOneRequest,
) -> Result[SystemOneResponse, SdkError] {
  let http_request : HttpRequest = {
    url: config.base_url + "/v1/systemone",
    http_method: "POST",
    headers: Map([
      ("authorization", "Bearer " + config.api_key),
      ("content-type", "application/json"),
    ]),
    body: encode_request_to_string(request),
  }
  match (transport.deliver)(http_request) {
    Err(NetworkFailure(message)) => Err(Network(message))
    Ok(response) => classify_response(response)
  }
}

///|
/// Evaluate with retries. `sleep_ms` is injected so tests run with zero
/// waiting and full observability; a real app passes its own timer. Retries
/// follow the verified policy: Retry-After is honored when present,
/// otherwise exponential backoff capped at `max_delay_ms`.
pub fn evaluate_with_retries(
  config : ClientConfig,
  transport : Transport,
  request : SystemOneRequest,
  sleep_ms : (Int) -> Unit,
) -> Result[SystemOneResponse, SdkError] {
  let mut attempts_done = 0
  let mut last : Result[SystemOneResponse, SdkError] = evaluate_once(
    config, transport, request,
  )
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
          last = evaluate_once(config, transport, request)
        } else {
          break
        }
    }
  }
  last
}
