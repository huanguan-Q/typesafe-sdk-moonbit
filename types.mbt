///|
/// Core types mirroring the TypeSafe System One HTTP contract
/// (https://docs.typesafe.ai/api). A request carries one `state` and one or
/// more named questions; the response answers each question by the same name.

///|
/// Token usage reported by the API. Input tokens are billable; output tokens
/// are currently free of charge.
pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
} derive(Debug)

///|
pub extend Usage with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Noul question: a yes/no judgment. The model answers with the probability
/// of yes in [0, 1].
pub(all) struct NoulQuestion {
  instructions : String
  yes_when : String?
  no_when : String?
} derive(Debug)

///|
pub extend NoulQuestion with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Choice question: pick one named option. The answer carries the selected
/// option, a confidence value, and the full probability distribution.
pub(all) struct ChoiceQuestion {
  instructions : String
  options : Map[String, String]
} derive(Debug)

///|
pub extend ChoiceQuestion with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Score question: rate against an ordered rubric. Level position determines
/// its score starting at zero; the answer is the probability-weighted
/// expected score (may fall between levels).
pub(all) struct ScoreQuestion {
  instructions : String
  levels : Array[String]
} derive(Debug)

///|
pub extend ScoreQuestion with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A question value. Box (image) questions are not supported in v0.1.
pub(all) enum Question {
  NoulQ(NoulQuestion)
  ChoiceQ(ChoiceQuestion)
  ScoreQ(ScoreQuestion)
} derive(Debug)

///|
pub extend Question with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// System One request: the model alias, the shared state, and the named
/// question set. Question names are yours; the response reuses them.
pub(all) struct SystemOneRequest {
  model : String
  state : String
  questions : Map[String, Question]
} derive(Debug)

///|
pub extend SystemOneRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A model answer. Its shape matches the question it was created from.
pub(all) enum Answer {
  NoulA(Double)
  ChoiceA(String, Double, Map[String, Double])
  ScoreA(Double, Double, Map[String, String], Map[String, Double])
} derive(Debug)

///|
pub extend Answer with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// System One response: the model that answered, per-question answers, and
/// token usage for the whole request.
pub(all) struct SystemOneResponse {
  model : String
  answers : Map[String, Answer]
  usage : Usage
} derive(Debug)

///|
pub extend SystemOneResponse with @moonbitlang/core/debug.Debug::{to_repr}
