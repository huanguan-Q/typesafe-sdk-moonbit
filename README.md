# typesafe-sdk-moonbit

Community MoonBit SDK for the [TypeSafe](https://typesafe.ai/) System One API
([Jev](https://docs.typesafe.ai/introduction)) — typed Noul / Choice / Score
questions, **formally verified confidence gates and retry policy**, and
network-free testing.

Independent community project. **Not affiliated with or endorsed by
TypeSafe AI.**

## Why this SDK exists

Every System One integration eventually hand-writes the same three pieces of
policy code: confidence gates, token budgets, and retry backoff. This SDK
proves them instead of hoping:

- `moon prove` (Why3 + Z3) discharges every decision core's contract —
  6 goals, 0 timeouts, including **budget dominance**: *an exhausted token
  budget blocks the decision at any confidence level*, and *fail-open never
  silently blocks while fail-closed never green-lights*.
- Gate math uses integer basis points (1.0 = 10000 bp), keeping every
  verified function inside the decidable linear-integer fragment. The public
  API still speaks `Double` probabilities via `to_bp` / `from_bp`.

Verified cores live in [`src/verified/verified.mbt`](src/verified/verified.mbt)
(dependency-free and Map-free by design so the Why3 module stays decidable);
`gates.mbt` / `retry.mbt` are thin enum-typed wrappers.

## Status

Experimental v0.1. Covered: Noul, Choice, and Score questions with typed
answers, request encoding, response decoding, status classification
(200 / 429 / 5xx / other), Retry-After (delay-seconds form) with exponential
backoff, scripted mock transport, and a `fetch` binding for JS targets.
Not covered: Box (image) questions, HTTP-date Retry-After, async retries.

## Install

Once published to mooncakes:

```
moon add hongguan/typesafe-sdk-moonbit
```

Until then, use a git path dependency in your `moon.mod` `import` block.

## Quick start

```moonbit
// 1) Build a typed request.
let questions : Map[String, Question] = Map([])
questions.set(
  "billing",
  Question::NoulQ({ instructions: "Is this message about billing?", yes_when: None, no_when: None }),
)
let request : SystemOneRequest =::{
  model: "jev-latest",
  state: "I was charged twice for my subscription.",
  questions,
}

// 2) Call the API through any transport — in production a real HTTP
//    client wrapped in `Transport`, in tests a `Transport::scripted`.
let (transport, calls) = Transport::scripted([/* ... */])
let config = ClientConfig::make(api_key=env_key)
let result = evaluate_with_retries(
  config,
  transport,
  request,
  fn(ms) { sleep(ms) }, // injected timer: tests pass a recorder instead
)

// 3) Gate the answer with verified policy.
match result {
  Ok(response) =>
    match response.answers.get("billing") {
      Some(Answer::NoulA(probability)) => {
        let verdict = noul_gate(to_bp(probability), 9000, 1000)
        let decision = decide(
          to_bp(probability),
          9000,                    // confidence threshold: 0.9
          response.usage.input_tokens,
          10000,                   // token budget for this workflow
        )
        // verdict / decision drive routing, escalation, or a hard stop.
      }
      _ => ()
    }
  Err(SdkError::RateLimited(retry_after)) => () // classified, retry-aware
  Err(_) => ()
}
```

Run the no-network demo: `moon run cmd/main`.

### JS targets (browser / Node / Deno / workers)

```moonbit
// import "hongguan/typesafe-sdk-moonbit/src/fetch"
// check/build with: moon check --target js
evaluate_async(config, request, fn(result) { /* callback */ })
```

Shipping an API key to a browser exposes it to every user; proxy through
your own backend in production web apps.

## Verified properties

| Function | Theorem (all discharged by Z3) |
| --- | --- |
| `decide_code` | Blocked ⟺ over budget; Proceed ⟺ in budget ∧ confidence ≥ threshold; Escalate ⟺ in budget ∧ below threshold. Budget dominates any confidence. |
| `noul_gate_code` | Each verdict code ⟺ its probability band. |
| `on_failure_code` | Blocked ⟺ fail-closed; never Proceed — a transport failure never yields a green light. |
| `should_retry` | Exactly `attempts_done < max_retries`. |
| `exp_delay` | Result stays within `[d, 2·max]`; overflow-safe for `max ≤ 2³⁰−1`. |
| `delay_ms` | Retry-After honored exactly; otherwise bounded by `[base, max]`. |

Reproduce: `moon prove` → expect `1 of 1 packages proved, 6 goals proved`.
Full chain: `moon check && moon test && moon build && moon prove`.

## Network-free testing

`Transport::scripted` answers from a list (last entry repeats) and records
every request — the whole SDK, including retry timing and headers, is tested
without sockets. See `typesafe-sdk-moonbit_test.mbt` (16 tests).

## Data egress

- Calling the real API sends your `state` and question texts (and nothing
  else) to `https://api.typesafe.ai` over HTTPS, authorized by your API key
  sent as a bearer header.
- The SDK itself makes no other network calls and includes no telemetry.
- Everything in this repository's tests and demo runs offline against
  scripted responses.

Keep API keys out of client-side code and out of version control; read them
from your environment or secret store.

## License

[MIT](LICENSE). Not affiliated with TypeSafe AI; TypeSafe and Jev are
trademarks of their respective owners.
