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
  let fields : Map[String, Json] = Map([
    ("model", Json::string(request.model)),
    ("state", Json::string(request.state)),
    ("questions", Json::object(questions)),
  ])
  if request.assets.length() > 0 {
    let assets : Map[String, Json] = Map([])
    request.assets.each(fn(name, asset) {
      assets.set(
        name,
        Json::object(
          Map([
            ("type", Json::string("image")),
            ("format", Json::string(asset.format)),
            ("data_base64", Json::string(asset.data_base64)),
          ]),
        ),
      )
    })
    fields.set("assets", Json::object(assets))
  }
  Json::object(fields)
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
    Question::BoxQ(bq) =>
      Json::object(
        Map([
          ("type", Json::string("box")),
          ("instructions", Json::string(bq.instructions)),
        ]),
      )
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
        Some(Json::String("box")) =>
          match fields.get("box") {
            Some(Json::Object(coords)) =>
              match
                (
                  get_number(coords, "top"),
                  get_number(coords, "bottom"),
                  get_number(coords, "left"),
                  get_number(coords, "right"),
                ) {
                (Some(top), Some(bottom), Some(left), Some(right)) => {
                  let confidence : Double? = match
                    get_number(fields, "confidence") {
                    Some(value) => Some(value)
                    None => None
                  }
                  Ok(
                    Answer::BoxA(
                      BoxCoords::{ top, bottom, left, right, },
                      confidence,
                    ),
                  )
                }
                _ => Err("box answer missing edge coordinates")
              }
            _ => Err("box answer missing box coordinates")
          }
        _ => Err("unsupported answer type")
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
