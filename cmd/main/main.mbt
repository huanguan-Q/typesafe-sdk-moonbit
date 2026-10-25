///|
/// Demo: a scripted 429 (HTTP-date Retry-After) → 200 round trip showing
/// clock-resolved retries driven by the verified policy, typed answers,
/// and formally verified gates. Runs on every target with no network.
fn main {
  let questions : Map[String, @lib.Question] = Map([])
  questions.set(
    "billing",
    @lib.Question::NoulQ({
      instructions: "Is this message about billing?",
      yes_when: None,
      no_when: None,
    }),
  )
  let request = @lib.SystemOneRequest::make(
    model="jev-latest",
    state="I was charged twice for my subscription this month.",
    questions~,
  )
  let (transport, calls) = @lib.Transport::scripted([
    Ok(@lib.HttpResponse::rate_limited_raw("Wed, 21 Oct 2015 07:28:00 GMT")),
    Ok(
      @lib.HttpResponse::ok_json(
        "{\"model\":\"jev-latest\",\"answers\":{\"billing\":{\"type\":\"noul\",\"noul\":0.98}},\"usage\":{\"input_tokens\":120,\"output_tokens\":12}}",
      ),
    ),
  ])
  let config = @lib.ClientConfig::make(api_key="demo-key")
  let sleeps : Array[Int] = []
  match
    @lib.evaluate_with_retries(
      config,
      transport,
      request,
      fn(ms : Int) {
        sleeps.push(ms)
        println("retrying after \{ms} ms (HTTP-date Retry-After honored)")
      },
      fn() { 1445412450 },
    ) {
    Ok(response) => {
      println(
        "model: \{response.model}, input tokens: \{response.usage.input_tokens}",
      )
      match response.answers.get("billing") {
        Some(@lib.Answer::NoulA(probability)) => {
          println("billing noul probability: \{probability}")
          let verdict = @lib.noul_gate(@lib.to_bp(probability), 9000, 1000)
          match verdict {
            Proceed => println("gate verdict: Proceed")
            Escalate => println("gate verdict: Escalate")
            Reject => println("gate verdict: Reject")
          }
          let decision = @lib.decide(
            @lib.to_bp(probability),
            9000,
            response.usage.input_tokens,
            10000,
          )
          match decision {
            Proceed => println("decision: Proceed")
            Escalate => println("decision: Escalate")
            Blocked => println("decision: Blocked")
          }
        }
        _ => println("no billing answer")
      }
    }
    Err(_) => println("request failed")
  }
  println("HTTP calls made: \{calls.length()}")
}
