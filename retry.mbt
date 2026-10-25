///|
/// Retry policy for transient failures (HTTP 429, 5xx, network errors).
///
/// The decision core (`should_retry`, `delay_ms`) is pure integer logic and
/// is formally verified with `moon prove` + Z3; only header parsing touches
/// strings.

///|
/// Retry configuration. `max_retries` counts retries after the first attempt.
pub(all) struct RetryPolicy {
  max_retries : Int
  base_delay_ms : Int
  max_delay_ms : Int
} derive(Debug)

///|
pub extend RetryPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Sensible defaults: 2 retries, 500 ms base delay, 30 s cap.
pub fn RetryPolicy::defaults() -> RetryPolicy {
  { max_retries: 2, base_delay_ms: 500, max_delay_ms: 30000, }
}

///|
/// Whether another retry is allowed after `attempts_done` attempts.
/// The contract is discharged by Z3 in the `src/verified` package.
pub fn should_retry(attempts_done : Int, max_retries : Int) -> Bool {
  @verified.should_retry(attempts_done, max_retries)
}

///|
/// Convenience wrapper: policy-aware `should_retry`.
pub fn retry_allowed(policy : RetryPolicy, attempts_done : Int) -> Bool {
  should_retry(attempts_done, policy.max_retries)
}

///|
/// Delay in milliseconds before the next retry.
///
/// When `retry_after_secs > 0` (a Retry-After header was received), the
/// server's directive is honored exactly: `retry_after_secs * 1000` ms, even
/// when it exceeds `max_delay_ms`. Otherwise the delay is exponential
/// backoff from `base_delay_ms`, capped at `max_delay_ms`. The three
/// theorems are discharged by Z3 in the `src/verified` package.
pub fn delay_ms(
  base_delay_ms : Int,
  max_delay_ms : Int,
  attempt : Int,
  retry_after_secs : Int,
) -> Int {
  @verified.delay_ms(base_delay_ms, max_delay_ms, attempt, retry_after_secs)
}

///|
/// Parse a Retry-After response header carrying delay-seconds (RFC 9110 §10.2.3).
/// The HTTP-date form is not supported in v0.1. Returns None when the header
/// is absent, non-numeric, or not a positive delay.
pub fn parse_retry_after(header : String?) -> Int? {
  match header {
    None => None
    Some(raw) => {
      let parsed : Int? = Some(@string.parse_int(raw.trim())) catch {
        _ => None
      }
      match parsed {
        Some(secs) => if secs > 0 { Some(secs) } else { None }
        None => None
      }
    }
  }
}
