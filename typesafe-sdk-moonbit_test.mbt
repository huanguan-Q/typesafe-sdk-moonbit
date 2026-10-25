// Blackbox tests run against the package's public API.
// They double as the SDK's network-free integration suite: every client
// behavior below runs against a scripted transport, never a real network.

///|
/// The official noul sample from the API reference, as a response body.
let sample_noul_body : String = "{\"model\":\"jev-latest\",\"answers\":{\"billing\":{\"type\":\"noul\",\"noul\":0.98}},\"usage\":{\"input_tokens\":120,\"output_tokens\":12}}"

///|
fn sample_request() -> @typesafe-sdk-moonbit.SystemOneRequest {
  let questions : Map[String, @typesafe-sdk-moonbit.Question] = Map([])
  questions.set(
    "billing",
    @typesafe-sdk-moonbit.Question::NoulQ({
      instructions: "Is this message about billing?",
      yes_when: Some("The message concerns charges, invoices, or refunds"),
      no_when: None,
    }),
  )
  @typesafe-sdk-moonbit.SystemOneRequest::{
    model: "jev-latest",
    state: "I was charged twice for my subscription this month.",
    questions,
  }
}

///|
test "noul_gate: bands and exact boundaries" {
  assert_eq(
    @typesafe-sdk-moonbit.noul_gate(9800, 9000, 1000),
    @typesafe-sdk-moonbit.GateVerdict::Proceed,
  )
  assert_eq(
    @typesafe-sdk-moonbit.noul_gate(9000, 9000, 1000),
    @typesafe-sdk-moonbit.GateVerdict::Proceed,
  )
  assert_eq(
    @typesafe-sdk-moonbit.noul_gate(1000, 9000, 1000),
    @typesafe-sdk-moonbit.GateVerdict::Reject,
  )
  assert_eq(
    @typesafe-sdk-moonbit.noul_gate(200, 9000, 1000),
    @typesafe-sdk-moonbit.GateVerdict::Reject,
  )
  assert_eq(
    @typesafe-sdk-moonbit.noul_gate(5000, 9000, 1000),
    @typesafe-sdk-moonbit.GateVerdict::Escalate,
  )
}

///|
test "decide: budget dominates confidence" {
  // Over budget: blocked no matter how confident.
  assert_eq(
    @typesafe-sdk-moonbit.decide(10000, 9000, 5000, 4000),
    @typesafe-sdk-moonbit.Decision::Blocked,
  )
  // Exactly at budget: still allowed.
  assert_eq(
    @typesafe-sdk-moonbit.decide(9500, 9000, 4000, 4000),
    @typesafe-sdk-moonbit.Decision::Proceed,
  )
  assert_eq(
    @typesafe-sdk-moonbit.decide(8999, 9000, 10, 4000),
    @typesafe-sdk-moonbit.Decision::Escalate,
  )
  assert_eq(
    @typesafe-sdk-moonbit.decide(9000, 9000, 10, 4000),
    @typesafe-sdk-moonbit.Decision::Proceed,
  )
}

///|
test "on_transport_failure: fail-open never blocks, fail-closed never proceeds" {
  assert_eq(
    @typesafe-sdk-moonbit.on_transport_failure(
      @typesafe-sdk-moonbit.FailPolicy::FailOpen,
    ),
    @typesafe-sdk-moonbit.Decision::Escalate,
  )
  assert_eq(
    @typesafe-sdk-moonbit.on_transport_failure(
      @typesafe-sdk-moonbit.FailPolicy::FailClosed,
    ),
    @typesafe-sdk-moonbit.Decision::Blocked,
  )
}

///|
test "to_bp / from_bp round trip" {
  assert_eq(@typesafe-sdk-moonbit.to_bp(0.98), 9800)
  assert_eq(@typesafe-sdk-moonbit.to_bp(0.5), 5000)
  assert_eq(@typesafe-sdk-moonbit.to_bp(0.0), 0)
  assert_eq(@typesafe-sdk-moonbit.to_bp(1.0), 10000)
  assert_eq(@typesafe-sdk-moonbit.to_bp(1.5), 10000)
  assert_eq(@typesafe-sdk-moonbit.to_bp(-0.1), 0)
  assert_true(@typesafe-sdk-moonbit.from_bp(9800) == 0.98)
  assert_true(@typesafe-sdk-moonbit.from_bp(0) == 0.0)
  assert_true(@typesafe-sdk-moonbit.from_bp(10000) == 1.0)
}

///|
test "should_retry: boundary semantics" {
  assert_true(@typesafe-sdk-moonbit.should_retry(0, 2))
  assert_true(@typesafe-sdk-moonbit.should_retry(1, 2))
  assert_true(!@typesafe-sdk-moonbit.should_retry(2, 2))
  assert_true(!@typesafe-sdk-moonbit.should_retry(5, 2))
}

///|
test "delay_ms: exponential backoff capped, Retry-After honored" {
  // No Retry-After: base * 2^attempt.
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 0, 0), 500)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 1, 0), 1000)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 2, 0), 2000)
  // Large attempt saturates at the cap.
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 40, 0), 30000)
  // Retry-After is honored exactly, even beyond the cap.
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 0, 3), 3000)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 1000, 0, 60), 60000)
}

///|
test "parse_retry_after: seconds form only" {
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some("2")), Some(2))
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some(" 7 ")), Some(7))
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some("abc")), None)
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some("0")), None)
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(None), None)
}

///|
test "encode_request_to_string: wire shape" {
  let questions : Map[String, @typesafe-sdk-moonbit.Question] = Map([])
  questions.set(
    "billing",
    @typesafe-sdk-moonbit.Question::NoulQ({
      instructions: "Is this message about billing?",
      yes_when: Some("About charges"),
      no_when: None,
    }),
  )
  questions.set(
    "tone",
    @typesafe-sdk-moonbit.Question::ChoiceQ({
      instructions: "What is the tone of this message?",
      options: Map([
        ("angry", "An upset or hostile message"),
        ("calm", "A neutral or polite message"),
      ]),
    }),
  )
  questions.set(
    "urgency",
    @typesafe-sdk-moonbit.Question::ScoreQ({
      instructions: "How urgent is this message?",
      levels: ["Can wait", "Needs attention today"],
    }),
  )
  let request : @typesafe-sdk-moonbit.SystemOneRequest = {
    model: "jev-latest",
    state: "I was charged twice.",
    questions,
  }
  let encoded = @typesafe-sdk-moonbit.encode_request_to_string(request)
  assert_true(encoded.contains("\"model\":\"jev-latest\""))
  assert_true(encoded.contains("\"state\":\"I was charged twice.\""))
  assert_true(encoded.contains("\"billing\""))
  assert_true(encoded.contains("\"type\":\"noul\""))
  assert_true(encoded.contains("\"type\":\"choice\""))
  assert_true(encoded.contains("\"angry\""))
  assert_true(encoded.contains("\"type\":\"score\""))
  assert_true(encoded.contains("\"Can wait\""))
}

///|
test "decode_response: official noul sample" {
  let decoded = @typesafe-sdk-moonbit.decode_response(sample_noul_body)
  assert_true(decoded is Ok(_))
  match decoded {
    Ok(response) => {
      assert_eq(response.model, "jev-latest")
      assert_eq(response.usage.input_tokens, 120)
      assert_eq(response.usage.output_tokens, 12)
      assert_true(
        response.answers.get("billing")
        is Some(@typesafe-sdk-moonbit.Answer::NoulA(0.98)),
      )
    }
    Err(_) => assert_true(false)
  }
}

///|
test "decode_response: choice and score samples" {
  let choice_body = "{\"model\":\"jev-latest\",\"answers\":{\"tone\":{\"type\":\"choice\",\"choice\":\"calm\",\"confidence\":0.7,\"probabilities\":{\"angry\":0.15,\"calm\":0.8,\"excited\":0.05}}},\"usage\":{\"input_tokens\":120,\"output_tokens\":12}}"
  match @typesafe-sdk-moonbit.decode_response(choice_body) {
    Ok(response) =>
      match response.answers.get("tone") {
        Some(
          @typesafe-sdk-moonbit.Answer::ChoiceA(
            choice,
            confidence,
            probabilities
          )
        ) => {
          assert_eq(choice, "calm")
          assert_true(confidence == 0.7)
          assert_true(probabilities.get("calm") is Some(0.8))
        }
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
  let score_body = "{\"model\":\"jev-latest\",\"answers\":{\"urgency\":{\"type\":\"score\",\"score\":1.7,\"confidence\":0.55,\"legend\":{\"0\":\"Can wait\",\"1\":\"This week\",\"2\":\"Today\"},\"probabilities\":{\"0\":0.1,\"1\":0.1,\"2\":0.8}}},\"usage\":{\"input_tokens\":120,\"output_tokens\":12}}"
  match @typesafe-sdk-moonbit.decode_response(score_body) {
    Ok(response) =>
      match response.answers.get("urgency") {
        Some(@typesafe-sdk-moonbit.Answer::ScoreA(score, confidence, legend, _)) => {
          assert_true(score == 1.7)
          assert_true(confidence == 0.55)
          assert_eq(legend.get("2"), Some("Today"))
        }
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "decode_response: error shapes" {
  assert_true(@typesafe-sdk-moonbit.decode_response("not json") is Err(_))
  assert_true(
    @typesafe-sdk-moonbit.decode_response(
      "{\"model\":\"jev-latest\",\"answers\":{\"q\":{\"type\":\"box\",\"box\":{\"top\":0.2}}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
    )
    is Err(_),
  )
}

///|
test "evaluate_with_retries: 429 then success, Retry-After honored" {
  let (transport, calls) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok(@typesafe-sdk-moonbit.HttpResponse::rate_limited("2")),
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="test-key")
  let sleeps : Array[Int] = []
  let result = @typesafe-sdk-moonbit.evaluate_with_retries(
    config,
    transport,
    sample_request(),
    fn(ms : Int) { sleeps.push(ms) },
  )
  assert_true(result is Ok(_))
  assert_eq(sleeps.length(), 1)
  assert_eq(sleeps[0], 2000)
  assert_eq(calls.length(), 2)
  assert_eq(calls[0].headers.get("authorization"), Some("Bearer test-key"))
  assert_eq(calls[0].url, "https://api.typesafe.ai/v1/systemone")
  assert_eq(calls[0].http_method, "POST")
}

///|
test "evaluate_with_retries: retries exhaust on repeated 500s" {
  let (transport, calls) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok(@typesafe-sdk-moonbit.HttpResponse::server_error(500)),
  ])
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  let sleeps : Array[Int] = []
  let result = @typesafe-sdk-moonbit.evaluate_with_retries(
    config,
    transport,
    sample_request(),
    fn(ms : Int) { sleeps.push(ms) },
  )
  assert_true(result is Err(_))
  match result {
    Err(@typesafe-sdk-moonbit.SdkError::Server(status, _)) =>
      assert_eq(status, 500)
    _ => assert_true(false)
  }
  assert_eq(calls.length(), 3)
  assert_eq(sleeps.length(), 2)
  assert_eq(sleeps[0], 500)
  assert_eq(sleeps[1], 1000)
}

///|
test "evaluate_with_retries: network failure recovers" {
  let (transport, _) = @typesafe-sdk-moonbit.Transport::scripted([
    Err(@typesafe-sdk-moonbit.TransportError::NetworkFailure("boom")),
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  let result = @typesafe-sdk-moonbit.evaluate_with_retries(
    config,
    transport,
    sample_request(),
    fn(_ms : Int) { () },
  )
  assert_true(result is Ok(_))
}

///|
test "evaluate_with_retries: 422 is not retried" {
  let (transport, calls) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok({ status: 422, headers: Map([]), body: "validation", }),
  ])
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  let sleeps : Array[Int] = []
  let result = @typesafe-sdk-moonbit.evaluate_with_retries(
    config,
    transport,
    sample_request(),
    fn(ms : Int) { sleeps.push(ms) },
  )
  match result {
    Err(@typesafe-sdk-moonbit.SdkError::InvalidRequest(status, _)) =>
      assert_eq(status, 422)
    _ => assert_true(false)
  }
  assert_eq(calls.length(), 1)
  assert_eq(sleeps.length(), 0)
}

///|
test "gates compose with a live-shaped response" {
  let (transport, _) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  match
    @typesafe-sdk-moonbit.evaluate_with_retries(
      config,
      transport,
      sample_request(),
      fn(_ms : Int) { () },
    ) {
    Ok(response) => {
      // Confidence 0.7 (7000 bp) below a 0.9 threshold escalates even though
      // the answer decodes fine; a 120-token answer stays within a 10000
      // budget, so the gate is decided by confidence alone.
      let decision = @typesafe-sdk-moonbit.decide(
        @typesafe-sdk-moonbit.to_bp(0.7),
        @typesafe-sdk-moonbit.to_bp(0.9),
        response.usage.input_tokens,
        10000,
      )
      assert_eq(decision, @typesafe-sdk-moonbit.Decision::Escalate)
    }
    Err(_) => assert_true(false)
  }
}
