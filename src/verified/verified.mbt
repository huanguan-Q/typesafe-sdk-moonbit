///|
/// Formally verified decision cores for the SDK.
///
/// This package is deliberately dependency-free and Map-free: pure integer
/// and Bool functions only, so the generated Why3 module stays inside the
/// decidable fragment that `moon prove` + Z3 discharges. Every public
/// function here carries a `where { proof_require / proof_ensure }`
/// contract; the root package exposes enum-typed wrappers over these cores.

///|
/// Noul gate core: 0 = Proceed, 1 = Escalate, 2 = Reject.
///
/// Verified: a 0 code implies `noul_bp >= high_bp`; a 2 code implies
/// `noul_bp <= low_bp`; a 1 code implies strictly between.
pub fn noul_gate_code(
  noul_bp : Int,
  high_bp : Int,
  low_bp : Int,
) -> Int where {
  proof_require: 0 <= low_bp && low_bp < high_bp && high_bp <= 10000,
  proof_ensure: result => {
    (result == 0) == (noul_bp >= high_bp) &&
    (result == 2) == (noul_bp <= low_bp) &&
    (result == 1) == (noul_bp > low_bp && noul_bp < high_bp)
  },
} {
  if noul_bp >= high_bp {
    0
  } else if noul_bp <= low_bp {
    2
  } else {
    1
  }
}

///|
/// Combined decision core: 0 = Proceed, 1 = Escalate, 2 = Blocked.
///
/// Verified theorems:
/// 1. Budget dominance — code 2 is returned only when
///    `tokens_used > token_budget`, at any confidence level.
/// 2. Code 0 requires being within budget *and* meeting the threshold.
/// 3. Code 1 means within budget but below the threshold.
pub fn decide_code(
  confidence_bp : Int,
  threshold_bp : Int,
  tokens_used : Int,
  token_budget : Int,
) -> Int where {
  proof_require: threshold_bp >= 0,
  proof_ensure: result => {
    (result == 2) == (tokens_used > token_budget) &&
    (result == 0) ==
    (tokens_used <= token_budget && confidence_bp >= threshold_bp) &&
    (result == 1) ==
    (tokens_used <= token_budget && confidence_bp < threshold_bp)
  },
} {
  if tokens_used > token_budget {
    2
  } else if confidence_bp >= threshold_bp {
    0
  } else {
    1
  }
}

///|
/// Transport-failure policy core: 1 = Escalate, 2 = Blocked.
///
/// Verified: the code is 2 exactly when the policy is fail-closed, and it
/// is never 0 — a transport failure never produces a green light.
pub fn on_failure_code(
  fail_closed : Bool,
) -> Int where {
  proof_ensure: result => (result == 2) == fail_closed && result != 0,
} {
  if fail_closed {
    2
  } else {
    1
  }
}

///|
/// Verified: whether another retry is allowed — exactly
/// `attempts_done < max_retries`.
pub fn should_retry(
  attempts_done : Int,
  max_retries : Int,
) -> Bool where {
  proof_require: attempts_done >= 0,
  proof_ensure: result => result == (attempts_done < max_retries),
} {
  attempts_done < max_retries
}

///|
/// Verified exponential helper: doubles `d` while below the cap until
/// `remaining` doublings are done. Stays within [d, 2 * max_delay_ms].
fn exp_delay(
  d : Int,
  remaining : Int,
  max_delay_ms : Int,
) -> Int where {
  proof_require: d >= 1 &&
  remaining >= 0 &&
  max_delay_ms >= 1 &&
  d <= max_delay_ms + max_delay_ms,
  proof_decrease: remaining,
  proof_ensure: result => result >= d && result <= max_delay_ms + max_delay_ms,
} {
  if remaining <= 0 {
    d
  } else if d >= max_delay_ms {
    exp_delay(d, remaining - 1, max_delay_ms)
  } else {
    exp_delay(d * 2, remaining - 1, max_delay_ms)
  }
}

///|
/// Retry delay core in milliseconds.
///
/// Verified theorems:
/// 1. With no Retry-After (`retry_after_secs <= 0`), the delay never
///    exceeds `max_delay_ms`.
/// 2. With a Retry-After, the delay is exactly the server's directive.
/// 3. With no Retry-After, the delay is at least `base_delay_ms`.
pub fn delay_ms(
  base_delay_ms : Int,
  max_delay_ms : Int,
  attempt : Int,
  retry_after_secs : Int,
) -> Int where {
  proof_require: base_delay_ms >= 1 &&
  max_delay_ms >= base_delay_ms &&
  attempt >= 0 &&
  max_delay_ms <= 1073741823,
  proof_ensure: result => {
    (retry_after_secs > 0 || result <= max_delay_ms) &&
    (retry_after_secs <= 0 || result == retry_after_secs * 1000) &&
    (retry_after_secs > 0 || result >= base_delay_ms)
  },
} {
  if retry_after_secs > 0 {
    retry_after_secs * 1000
  } else {
    let grown = exp_delay(base_delay_ms, attempt, max_delay_ms)
    if grown > max_delay_ms {
      max_delay_ms
    } else {
      grown
    }
  }
}
