// Blackbox tests run against the package's public API.
// They double as the SDK's network-free integration suite: every client
// behavior below runs against a scripted transport, never a real network.

///|
/// The official noul sample from the API reference, as a response body.
let sample_noul_body : String = "{\"model\":\"jev-latest\",\"answers\":{\"billing\":{\"type\":\"noul\",\"noul\":0.98}},\"usage\":{\"input_tokens\":120,\"output_tokens\":12}}"

///|
/// A fixed instant 30 s before the 2015-10-21T07:28:00Z fixture date.
let fixture_now : Int = 1445412450

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
  @typesafe-sdk-moonbit.SystemOneRequest::make(
    model="jev-latest",
    state="I was charged twice for my subscription this month.",
    questions~,
  )
}

///|
fn no_clock() -> Int {
  0
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
  assert_eq(
    @typesafe-sdk-moonbit.decide(10000, 9000, 5000, 4000),
    @typesafe-sdk-moonbit.Decision::Blocked,
  )
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
test "delay_ms: exponential backoff capped, directives honored exactly" {
  // No directive (-1): base * 2^attempt, capped at max.
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 0, -1), 500)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 1, -1), 1000)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 2, -1), 2000)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 40, -1), 30000)
  // Directive 0 means retry immediately.
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 0, 0), 0)
  // Directives are honored exactly, even beyond the cap.
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 30000, 0, 3), 3000)
  assert_eq(@typesafe-sdk-moonbit.delay_ms(500, 1000, 0, 60), 60000)
}

///|
test "days_from_civil: known epochs" {
  assert_eq(@typesafe-sdk-moonbit.days_from_civil(1970, 1, 1), 0)
  assert_eq(@typesafe-sdk-moonbit.days_from_civil(2000, 3, 1), 11017)
  assert_eq(@typesafe-sdk-moonbit.days_from_civil(2015, 10, 21), 16729)
}

///|
test "parse_retry_after: seconds and HTTP-date forms" {
  // Delay-seconds.
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some("2"), 0), Some(2))
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some(" 7 "), 0), Some(7))
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some("0"), 0), Some(0))
  // IMF-fixdate resolved against the clock: 30 s in the future.
  assert_eq(
    @typesafe-sdk-moonbit.parse_retry_after(
      Some("Wed, 21 Oct 2015 07:28:00 GMT"),
      fixture_now,
    ),
    Some(30),
  )
  // Date already in the past clamps to zero, never negative.
  assert_eq(
    @typesafe-sdk-moonbit.parse_retry_after(
      Some("Wed, 21 Oct 2015 07:28:00 GMT"),
      1445412480 + 600,
    ),
    Some(0),
  )
  // Absent or unparseable.
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(None, 0), None)
  assert_eq(@typesafe-sdk-moonbit.parse_retry_after(Some("abc"), 0), None)
  assert_eq(
    @typesafe-sdk-moonbit.parse_retry_after(
      Some("Tuesday, 21-Oct-15 07:28:00 GMT"),
      0,
    ),
    None,
  )
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
  let request = @typesafe-sdk-moonbit.SystemOneRequest::make(
    model="jev-latest",
    state="I was charged twice.",
    questions~,
  )
  let encoded = @typesafe-sdk-moonbit.encode_request_to_string(request)
  assert_true(encoded.contains("\"model\":\"jev-latest\""))
  assert_true(encoded.contains("\"state\":\"I was charged twice.\""))
  assert_true(encoded.contains("\"billing\""))
  assert_true(encoded.contains("\"type\":\"noul\""))
  assert_true(encoded.contains("\"type\":\"choice\""))
  assert_true(encoded.contains("\"angry\""))
  assert_true(encoded.contains("\"type\":\"score\""))
  assert_true(encoded.contains("\"Can wait\""))
  assert_true(!encoded.contains("\"assets\""))
}

///|
test "encode_request_to_string: box question and image asset" {
  let questions : Map[String, @typesafe-sdk-moonbit.Question] = Map([])
  questions.set(
    "red_rectangle",
    @typesafe-sdk-moonbit.Question::BoxQ({
      instructions: "Locate the red rectangle.",
    }),
  )
  let request : @typesafe-sdk-moonbit.SystemOneRequest = {
    model: "jev-preview",
    state: "photo",
    questions,
    assets: Map([("photo", { format: "png", data_base64: "iVBORw0KGgo=", })]),
  }
  let encoded = @typesafe-sdk-moonbit.encode_request_to_string(request)
  assert_true(encoded.contains("\"type\":\"box\""))
  assert_true(encoded.contains("Locate the red rectangle."))
  assert_true(encoded.contains("\"assets\""))
  assert_true(encoded.contains("\"photo\""))
  assert_true(encoded.contains("\"data_base64\":\"iVBORw0KGgo=\""))
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
  let score_body = "{\"model\":\"jev-latest\",\"answers\":{\"urgency\":{\"type\":\"score\",\"score\":1.7,\"confidence\":0.55,\"legend\":{\"0\":\"Can wait\",\"1\":\"This week\",\"2\":\"Today\"},\"probabilities\":{\"0\":0.1,\"1\":0.1,\"2\":0.8}}},\"usage\":{\"input_tokens\":120,\"output_tokens\":12},\"sort_keys\":false}"
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
test "decode_response: box answer, confidence present and absent" {
  let null_confidence = "{\"model\":\"jev-preview\",\"answers\":{\"red_rectangle\":{\"type\":\"box\",\"box\":{\"top\":0.2,\"bottom\":0.66,\"left\":0.19,\"right\":0.68},\"confidence\":null}},\"usage\":{\"input_tokens\":285,\"output_tokens\":20}}"
  match @typesafe-sdk-moonbit.decode_response(null_confidence) {
    Ok(response) =>
      match response.answers.get("red_rectangle") {
        Some(@typesafe-sdk-moonbit.Answer::BoxA(coords, confidence)) => {
          assert_true(coords.top == 0.2)
          assert_true(coords.bottom == 0.66)
          assert_true(coords.left == 0.19)
          assert_true(coords.right == 0.68)
          assert_true(confidence is None)
        }
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
  let with_confidence = "{\"model\":\"jev-preview\",\"answers\":{\"r\":{\"type\":\"box\",\"box\":{\"top\":0.1,\"bottom\":0.5,\"left\":0.1,\"right\":0.5},\"confidence\":0.9}},\"usage\":{\"input_tokens\":100,\"output_tokens\":10}}"
  match @typesafe-sdk-moonbit.decode_response(with_confidence) {
    Ok(response) =>
      match response.answers.get("r") {
        Some(@typesafe-sdk-moonbit.Answer::BoxA(_, confidence)) =>
          assert_true(confidence is Some(0.9))
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
      "{\"model\":\"jev-latest\",\"answers\":{\"q\":{\"type\":\"telepathy\"}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
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
    no_clock,
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
test "evaluate_with_retries: HTTP-date Retry-After resolved via clock" {
  let (transport, calls) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok(
      @typesafe-sdk-moonbit.HttpResponse::rate_limited_raw(
        "Wed, 21 Oct 2015 07:28:00 GMT",
      ),
    ),
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  let sleeps : Array[Int] = []
  let result = @typesafe-sdk-moonbit.evaluate_with_retries(
    config,
    transport,
    sample_request(),
    fn(ms : Int) { sleeps.push(ms) },
    fn() { fixture_now },
  )
  assert_true(result is Ok(_))
  assert_eq(sleeps.length(), 1)
  assert_eq(sleeps[0], 30000)
  assert_eq(calls.length(), 2)
}

///|
test "evaluate_with_retries: danger-zone header only with assets" {
  let box_questions : Map[String, @typesafe-sdk-moonbit.Question] = Map([])
  box_questions.set(
    "r",
    @typesafe-sdk-moonbit.Question::BoxQ({ instructions: "Find it.", }),
  )
  let box_request : @typesafe-sdk-moonbit.SystemOneRequest = {
    model: "jev-preview",
    state: "photo",
    questions: box_questions,
    assets: Map([("photo", { format: "png", data_base64: "AAAA", })]),
  }
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  // With assets: the danger-zone header is sent and assets are encoded.
  let (t1, calls1) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let _ = @typesafe-sdk-moonbit.evaluate_once(config, t1, box_request, no_clock)
  assert_eq(calls1[0].headers.get("typesafe-danger-zone-images"), Some("true"))
  assert_true(calls1[0].body.contains("\"assets\""))
  // Without assets: the header is absent.
  let (t2, calls2) = @typesafe-sdk-moonbit.Transport::scripted([
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let _ = @typesafe-sdk-moonbit.evaluate_once(
    config,
    t2,
    sample_request(),
    no_clock,
  )
  assert_true(calls2[0].headers.get("typesafe-danger-zone-images") is None)
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
    no_clock,
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
    no_clock,
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
    no_clock,
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
test "evaluate_with_retries_async: full flows without blocking" {
  let config = @typesafe-sdk-moonbit.ClientConfig::make(api_key="k")
  // 429 with an HTTP-date header, then success.
  let (transport, calls) = @typesafe-sdk-moonbit.AsyncTransport::scripted([
    Ok(
      @typesafe-sdk-moonbit.HttpResponse::rate_limited_raw(
        "Wed, 21 Oct 2015 07:28:00 GMT",
      ),
    ),
    Ok(@typesafe-sdk-moonbit.HttpResponse::ok_json(sample_noul_body)),
  ])
  let sleeps : Array[Int] = []
  let outcomes : Array[Bool] = []
  @typesafe-sdk-moonbit.evaluate_with_retries_async(
    config,
    transport,
    sample_request(),
    fn(ms : Int, wake : () -> Unit) {
      sleeps.push(ms)
      wake()
    },
    fn() { fixture_now },
    fn(result) { outcomes.push(result is Ok(_)) },
  )
  assert_eq(outcomes.length(), 1)
  assert_true(outcomes[0])
  assert_eq(sleeps.length(), 1)
  assert_eq(sleeps[0], 30000)
  assert_eq(calls.length(), 2)
  // Exhausted retries on 5xx.
  let (transport2, calls2) = @typesafe-sdk-moonbit.AsyncTransport::scripted([
    Ok(@typesafe-sdk-moonbit.HttpResponse::server_error(503)),
  ])
  let sleeps2 : Array[Int] = []
  let outcomes2 : Array[Bool] = []
  @typesafe-sdk-moonbit.evaluate_with_retries_async(
    config,
    transport2,
    sample_request(),
    fn(ms : Int, wake : () -> Unit) {
      sleeps2.push(ms)
      wake()
    },
    no_clock,
    fn(result) { outcomes2.push(result is Err(_)) },
  )
  assert_eq(outcomes2.length(), 1)
  assert_true(outcomes2[0])
  assert_eq(calls2.length(), 3)
  assert_eq(sleeps2.length(), 2)
  assert_eq(sleeps2[0], 500)
  assert_eq(sleeps2[1], 1000)
  // Non-retryable failure completes immediately.
  let (transport3, calls3) = @typesafe-sdk-moonbit.AsyncTransport::scripted([
    Ok({ status: 422, headers: Map([]), body: "validation", }),
  ])
  let outcomes3 : Array[Bool] = []
  @typesafe-sdk-moonbit.evaluate_with_retries_async(
    config,
    transport3,
    sample_request(),
    fn(_ms : Int, wake : () -> Unit) { wake() },
    no_clock,
    fn(result) { outcomes3.push(result is Err(_)) },
  )
  assert_eq(outcomes3.length(), 1)
  assert_eq(calls3.length(), 1)
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
      no_clock,
    ) {
    Ok(response) => {
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
