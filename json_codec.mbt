///|
/// JSON encoding of requests and decoding of responses, hand-mapped onto the
/// builtin `Json` type so the wire format stays explicit and testable.

///|
/// Encode a request to its JSON wire form.
pub fn encode_request_to_string(request : SystemOneRequest) -> String {
  encode_request(request).stringify()
}

///|
fn encode_request(request : SystemOneRequest) -> Json {
  let questions : Map[String, Json] = Map([])
  request.questions.each(fn(name, question) {
    questions.set(name, encode_question(question))
  })
  Json::object(
    Map([
      ("model", Json::string(request.model)),
      ("state", Json::string(request.state)),
      ("questions", Json::object(questions)),
    ]),
  )
}

///|
fn encode_question(question : Question) -> Json {
  match question {
    Question::NoulQ(nq) => {
      let criteria : Map[String, Json] = Map([])
      match nq.yes_when {
        Some(text) => criteria.set("true", Json::string(text))
        None => ()
      }
      match nq.no_when {
        Some(text) => criteria.set("false", Json::string(text))
        None => ()
      }
      let fields : Map[String, Json] = Map([
        ("type", Json::string("noul")),
        ("instructions", Json::string(nq.instructions)),
      ])
      if criteria.length() > 0 {
        fields.set("criteria", Json::object(criteria))
      }
      Json::object(fields)
    }
    Question::ChoiceQ(cq) => {
      let options : Map[String, Json] = Map([])
      cq.options.each(fn(name, description) {
        options.set(name, Json::string(description))
      })
      Json::object(
        Map([
          ("type", Json::string("choice")),
          ("instructions", Json::string(cq.instructions)),
          ("criteria", Json::object(options)),
        ]),
      )
    }
    Question::ScoreQ(sq) => {
      let levels : Array[Json] = []
      for level in sq.levels {
        levels.push(Json::string(level))
      }
      Json::object(
        Map([
          ("type", Json::string("score")),
          ("instructions", Json::string(sq.instructions)),
          ("criteria", Json::array(levels)),
        ]),
      )
    }
  }
}

///|
fn get_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

///|
fn get_number(fields : Map[String, Json], key : String) -> Double? {
  match fields.get(key) {
    Some(Json::Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn get_int(fields : Map[String, Json], key : String) -> Int? {
  match get_number(fields, key) {
    Some(value) => Some(value.to_int())
    None => None
  }
}

///|
fn decode_string_map(raw : Map[String, Json]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  raw.each(fn(key, value) {
    match value {
      Json::String(text) => out.set(key, text)
      _ => ()
    }
  })
  out
}

///|
fn decode_double_map(raw : Map[String, Json]) -> Map[String, Double] {
  let out : Map[String, Double] = Map([])
  raw.each(fn(key, value) {
    match value {
      Json::Number(value, ..) => out.set(key, value)
      _ => ()
    }
  })
  out
}

///|
fn decode_answer(answer : Json) -> Result[Answer, String] {
  match answer {
    Json::Object(fields) =>
      match fields.get("type") {
        Some(Json::String("noul")) =>
          match get_number(fields, "noul") {
            Some(probability) => Ok(Answer::NoulA(probability))
            None => Err("noul answer missing probability")
          }
        Some(Json::String("choice")) =>
          match
            (
              get_string(fields, "choice"),
              get_number(fields, "confidence"),
              fields.get("probabilities"),
            ) {
            (Some(choice), Some(confidence), Some(Json::Object(probabilities))) =>
              Ok(
                Answer::ChoiceA(
                  choice,
                  confidence,
                  decode_double_map(probabilities),
                ),
              )
            _ => Err("choice answer missing fields")
          }
        Some(Json::String("score")) =>
          match
            (
              get_number(fields, "score"),
              get_number(fields, "confidence"),
              fields.get("legend"),
              fields.get("probabilities"),
            ) {
            (
              Some(score),
              Some(confidence),
              Some(Json::Object(legend)),
              Some(Json::Object(probabilities)),
            ) =>
              Ok(
                Answer::ScoreA(
                  score,
                  confidence,
                  decode_string_map(legend),
                  decode_double_map(probabilities),
                ),
              )
            _ => Err("score answer missing fields")
          }
        _ => Err("unsupported answer type (box/image questions not in v0.1)")
      }
    _ => Err("answer is not a JSON object")
  }
}

///|
/// Decode a System One response body. Answer names are matched back to the
/// question names you chose; unknown shapes surface as `SdkError::Decode`.
pub fn decode_response(body : String) -> Result[SystemOneResponse, SdkError] {
  let parsed : Result[Json, String] = Ok(@json.parse(body)) catch {
    e => Err("invalid JSON: \{e}")
  }
  match parsed {
    Err(message) => Err(SdkError::Decode(message))
    Ok(Json::Object(fields)) =>
      match
        (
          get_string(fields, "model"),
          fields.get("answers"),
          fields.get("usage"),
        ) {
        (Some(model), Some(Json::Object(answers)), Some(Json::Object(usage))) => {
          let decoded : Map[String, Answer] = Map([])
          let problems : Array[String] = []
          answers.each(fn(name, value) {
            match decode_answer(value) {
              Ok(answer) => decoded.set(name, answer)
              Err(message) => problems.push(name + ": " + message)
            }
          })
          if problems.length() > 0 {
            return Err(SdkError::Decode(problems[0]))
          }
          match
            (get_int(usage, "input_tokens"), get_int(usage, "output_tokens")) {
            (Some(input), Some(output)) =>
              Ok(SystemOneResponse::{
                model,
                answers: decoded,
                usage: Usage::{ input_tokens: input, output_tokens: output, },
              })
            _ => Err(SdkError::Decode("usage missing token counts"))
          }
        }
        _ => Err(SdkError::Decode("response missing model/answers/usage"))
      }
    Ok(_) => Err(SdkError::Decode("response body is not a JSON object"))
  }
}
