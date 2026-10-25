///|
/// Confidence gates, token-budget guards, and failure policies.
///
/// All gate mathematics uses integer basis points (probability 1.0 = 10000
/// bp) so every decision core is a pure integer function in the formally
/// verifiable domain: `moon prove` discharges each contract with Z3. The
/// public enum API wraps these verified cores; the wrapper is a trivial
/// code-to-constructor mapping, and the theorems live on the cores:
///
/// - budget dominance: an exhausted token budget blocks a decision at any
///   confidence level,
/// - fail-open never silently blocks and fail-closed never proceeds,
/// - every gate verdict implies its probability band.

///|
/// Verdict of a standalone gate evaluation.
pub(all) enum GateVerdict {
  Proceed
  Escalate
  Reject
} derive(Debug, Eq)

///|
pub extend GateVerdict with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend GateVerdict with Eq::{equal, not_equal}

///|
/// Combined decision: confidence threshold plus token budget plus policy.
pub(all) enum Decision {
  Proceed
  Escalate
  Blocked
} derive(Debug, Eq)

///|
pub extend Decision with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Decision with Eq::{equal, not_equal}

///|
/// What to do when the transport or API fails outright.
/// FailOpen lets the action continue under human review; FailClosed stops it.
pub(all) enum FailPolicy {
  FailOpen
  FailClosed
} derive(Debug, Eq)

///|
pub extend FailPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FailPolicy with Eq::{equal, not_equal}

///|
/// Verified core of `noul_gate`: 0 = Proceed, 1 = Escalate, 2 = Reject.
/// The contract is discharged by Z3 in the `src/verified` package.
pub fn noul_gate_code(noul_bp : Int, high_bp : Int, low_bp : Int) -> Int {
  @verified.noul_gate_code(noul_bp, high_bp, low_bp)
}

///|
/// Two-threshold gate for Noul (probability-of-yes) answers, in basis
/// points. At or above `high_bp` → Proceed; at or below `low_bp` → Reject;
/// strictly between → Escalate (uncertain band).
pub fn noul_gate(noul_bp : Int, high_bp : Int, low_bp : Int) -> GateVerdict {
  match noul_gate_code(noul_bp, high_bp, low_bp) {
    0 => GateVerdict::Proceed
    2 => GateVerdict::Reject
    _ => GateVerdict::Escalate
  }
}

///|
/// Verified core of `decide`: 0 = Proceed, 1 = Escalate, 2 = Blocked.
/// The contract (including budget dominance) is discharged by Z3 in the
/// `src/verified` package.
pub fn decide_code(
  confidence_bp : Int,
  threshold_bp : Int,
  tokens_used : Int,
  token_budget : Int,
) -> Int {
  @verified.decide_code(confidence_bp, threshold_bp, tokens_used, token_budget)
}

///|
/// Combined decision from an answer's confidence and the caller's token
/// budget, in basis points. See `decide_code` for the verified properties.
pub fn decide(
  confidence_bp : Int,
  threshold_bp : Int,
  tokens_used : Int,
  token_budget : Int,
) -> Decision {
  match decide_code(confidence_bp, threshold_bp, tokens_used, token_budget) {
    0 => Decision::Proceed
    2 => Decision::Blocked
    _ => Decision::Escalate
  }
}

///|
/// Verified core of `on_transport_failure`: 1 = Escalate, 2 = Blocked.
/// The contract is discharged by Z3 in the `src/verified` package.
pub fn on_failure_code(fail_closed : Bool) -> Int {
  @verified.on_failure_code(fail_closed)
}

///|
/// Decision to take when the transport or API failed and no answer exists.
/// FailOpen escalates to human review; FailClosed blocks.
pub fn on_transport_failure(policy : FailPolicy) -> Decision {
  let fail_closed : Bool = match policy {
    FailPolicy::FailOpen => false
    FailPolicy::FailClosed => true
  }
  match on_failure_code(fail_closed) {
    2 => Decision::Blocked
    _ => Decision::Escalate
  }
}

///|
/// Convert a probability in [0, 1] to basis points, rounding to nearest.
/// Values outside [0, 1] are clamped.
pub fn to_bp(probability : Double) -> Int {
  if probability <= 0.0 {
    0
  } else if probability >= 1.0 {
    10000
  } else {
    (probability * 10000.0 + 0.5).to_int()
  }
}

///|
/// Convert basis points back to a probability, clamped to [0, 1].
pub fn from_bp(bp : Int) -> Double {
  if bp <= 0 {
    0.0
  } else if bp >= 10000 {
    1.0
  } else {
    bp.to_double() / 10000.0
  }
}
