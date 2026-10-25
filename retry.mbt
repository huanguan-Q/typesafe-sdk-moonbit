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
/// A Retry-After directive (`retry_after_secs >= 0`, where 0 means retry
/// immediately) is honored exactly: `retry_after_secs * 1000` ms, even when
/// it exceeds `max_delay_ms`. Without a directive (negative value), the
/// delay is exponential backoff from `base_delay_ms`, capped at
/// `max_delay_ms`. The three theorems are discharged by Z3 in the
/// `src/verified` package.
pub fn delay_ms(
  base_delay_ms : Int,
  max_delay_ms : Int,
  attempt : Int,
  retry_after_secs : Int,
) -> Int {
  @verified.delay_ms(base_delay_ms, max_delay_ms, attempt, retry_after_secs)
}

///|
fn try_parse_int_view(text : StringView) -> Int? {
  Some(@string.parse_int(text)) catch {
    _ => None
  }
}

///|
/// Days since 1970-01-01 for a civil (proleptic Gregorian) date — Howard
/// Hinnant's `days_from_civil`, valid for years >= 1. Pure integer
/// arithmetic, runtime-tested against known epochs.
pub fn days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (month + 9) % 12
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
fn month_from_name(name : StringView) -> Int? {
  if name.equal_to_string("Jan") {
    Some(1)
  } else if name.equal_to_string("Feb") {
    Some(2)
  } else if name.equal_to_string("Mar") {
    Some(3)
  } else if name.equal_to_string("Apr") {
    Some(4)
  } else if name.equal_to_string("May") {
    Some(5)
  } else if name.equal_to_string("Jun") {
    Some(6)
  } else if name.equal_to_string("Jul") {
    Some(7)
  } else if name.equal_to_string("Aug") {
    Some(8)
  } else if name.equal_to_string("Sep") {
    Some(9)
  } else if name.equal_to_string("Oct") {
    Some(10)
  } else if name.equal_to_string("Nov") {
    Some(11)
  } else if name.equal_to_string("Dec") {
    Some(12)
  } else {
    None
  }
}

///|
/// Parse an IMF-fixdate — `Wed, 21 Oct 2015 07:28:00 GMT`, a fixed-width
/// 29-character format — into seconds since the Unix epoch. The two
/// deprecated date formats (RFC 850, asctime) are not accepted.
pub fn parse_http_date_secs(raw : String) -> Int? {
  let s = raw.trim()
  if s.length() != 29 {
    return None
  }
  // Layout: WWW, DD Mon YYYY HH:MM:SS GMT
  let comma = s.exact_view(start=3, end=4)
  let sp1 = s.exact_view(start=4, end=5)
  let sp2 = s.exact_view(start=7, end=8)
  let sp3 = s.exact_view(start=11, end=12)
  let sp4 = s.exact_view(start=16, end=17)
  let colon1 = s.exact_view(start=19, end=20)
  let colon2 = s.exact_view(start=22, end=23)
  let sp5 = s.exact_view(start=25, end=26)
  let tz = s.exact_view(start=26, end=29)
  if !(comma.equal_to_string(",") &&
    sp1.equal_to_string(" ") &&
    sp2.equal_to_string(" ") &&
    sp3.equal_to_string(" ") &&
    sp4.equal_to_string(" ") &&
    colon1.equal_to_string(":") &&
    colon2.equal_to_string(":") &&
    sp5.equal_to_string(" ") &&
    tz.equal_to_string("GMT")) {
    return None
  }
  let day = try_parse_int_view(s.exact_view(start=5, end=7))
  let month = month_from_name(s.exact_view(start=8, end=11))
  let year = try_parse_int_view(s.exact_view(start=12, end=16))
  let hour = try_parse_int_view(s.exact_view(start=17, end=19))
  let minute = try_parse_int_view(s.exact_view(start=20, end=22))
  let second = try_parse_int_view(s.exact_view(start=23, end=25))
  match (day, month, year, hour, minute, second) {
    (Some(day), Some(month), Some(year), Some(hour), Some(minute), Some(second)) =>
      if day >= 1 &&
        day <= 31 &&
        month >= 1 &&
        month <= 12 &&
        year >= 1970 &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59 &&
        second >= 0 &&
        second <= 59 {
        Some(
          days_from_civil(year, month, day) * 86400 +
          hour * 3600 +
          minute * 60 +
          second,
        )
      } else {
        None
      }
    _ => None
  }
}

///|
/// Parse a Retry-After response header (RFC 9110 §10.2.3). Accepts both
/// forms: delay-seconds (`"120"`; `"0"` means retry immediately) and
/// IMF-fixdate (`"Wed, 21 Oct 2015 07:28:00 GMT"`), resolved against
/// `now_secs` — a date already in the past yields `Some(0)`, never a
/// negative delay. Returns None when the header is absent or unparseable.
pub fn parse_retry_after(header : String?, now_secs : Int) -> Int? {
  match header {
    None => None
    Some(raw) => {
      let trimmed = raw.trim()
      let numeric : Int? = try_parse_int_view(trimmed)
      match numeric {
        Some(secs) => if secs >= 0 { Some(secs) } else { None }
        None =>
          match parse_http_date_secs(raw) {
            Some(at_secs) => {
              let delay = at_secs - now_secs
              if delay > 0 {
                Some(delay)
              } else {
                Some(0)
              }
            }
            None => None
          }
      }
    }
  }
}
