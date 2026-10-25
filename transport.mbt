///|
/// Transport abstraction and SDK errors.
///
/// A `Transport` is a single closure field, so any HTTP client — including a
/// mock in tests — can adapt to the SDK with zero dependencies. This is what
/// makes the whole SDK testable without network access.

///|
/// An outbound HTTP request. Header keys are expected to be lowercased.
pub(all) struct HttpRequest {
  url : String
  http_method : String
  headers : Map[String, String]
  body : String
} derive(Debug)

///|
pub extend HttpRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An HTTP response. Header keys should be lowercased by the transport so
/// lookups like `retry-after` are case-insensitive.
pub(all) struct HttpResponse {
  status : Int
  headers : Map[String, String]
  body : String
} derive(Debug)

///|
pub extend HttpResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Transport-level failure: DNS, connection, timeout, and similar errors
/// that carry no HTTP status.
pub(all) enum TransportError {
  NetworkFailure(String)
} derive(Debug)

///|
pub extend TransportError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Pluggable HTTP transport. Wrap any client into the `deliver` closure.
pub(all) struct Transport {
  deliver : (HttpRequest) -> Result[HttpResponse, TransportError]
}

///|
/// SDK-level error after transport, HTTP status classification, and decoding.
pub(all) enum SdkError {
  Network(String)
  RateLimited(Int?)
  Server(Int, String)
  InvalidRequest(Int, String)
  Decode(String)
} derive(Debug)

///|
pub extend SdkError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 200 OK with a JSON body.
pub fn HttpResponse::ok_json(body : String) -> HttpResponse {
  { status: 200, headers: Map([]), body, }
}

///|
/// 429 Too Many Requests with a Retry-After header in seconds.
pub fn HttpResponse::rate_limited(retry_after_secs : String) -> HttpResponse {
  { status: 429, headers: Map([("retry-after", retry_after_secs)]), body: "", }
}

///|
/// A 5xx server error with the given status.
pub fn HttpResponse::server_error(status : Int) -> HttpResponse {
  { status, headers: Map([]), body: "server error", }
}

///|
/// Build a scripted transport for network-free tests: responses are consumed
/// in order and the last one repeats. Returns the transport together with a
/// call log recording every request it saw.
pub fn Transport::scripted(
  responses : Array[Result[HttpResponse, TransportError]],
) -> (Transport, Array[HttpRequest]) {
  let calls : Array[HttpRequest] = []
  let transport : Transport = {
    deliver: fn(request : HttpRequest) -> Result[HttpResponse, TransportError] {
      let index = calls.length()
      calls.push(request)
      if responses.length() == 0 {
        Err(TransportError::NetworkFailure("mock: no scripted responses"))
      } else if index < responses.length() {
        responses[index]
      } else {
        responses[responses.length() - 1]
      }
    },
  }
  (transport, calls)
}
