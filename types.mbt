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
/// A question value. Box questions locate a region in an image asset and
/// require the TypeSafe-Danger-Zone-Images header, which the client sends
/// automatically when the request carries assets.
pub(all) enum Question {
  NoulQ(NoulQuestion)
  ChoiceQ(ChoiceQuestion)
  ScoreQ(ScoreQuestion)
  BoxQ(BoxQuestion)
} derive(Debug)

///|
pub extend Question with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Box question: locate what the instructions describe in an image asset
/// referenced by placeholder. Answers are normalized edge coordinates.
pub(all) struct BoxQuestion {
  instructions : String
} derive(Debug)

///|
pub extend BoxQuestion with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An image asset, keyed by an opaque placeholder you reference from state
/// or question text. Base64 form only: multipart part-based assets are not
/// supported in v0.2. Image data is sent to the API (see README data egress).
pub(all) struct ImageAsset {
  format : String
  data_base64 : String
} derive(Debug)

///|
pub extend ImageAsset with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Box edges as fractions of image height/width, 0 to 1. Vertical from the
/// top, horizontal from the left.
pub(all) struct BoxCoords {
  top : Double
  bottom : Double
  left : Double
  right : Double
} derive(Debug)

///|
pub extend BoxCoords with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// System One request: the model alias, the shared state, the named
/// question set, and optional image assets. Question names are yours; the
/// response reuses them.
pub(all) struct SystemOneRequest {
  model : String
  state : String
  questions : Map[String, Question]
  assets : Map[String, ImageAsset]
} derive(Debug)

///|
/// Build a request with no image assets.
pub fn SystemOneRequest::make(
  model~ : String,
  state~ : String,
  questions~ : Map[String, Question],
) -> SystemOneRequest {
  { model, state, questions, assets: Map([]), }
}

///|
pub extend SystemOneRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A model answer. Its shape matches the question it was created from.
pub(all) enum Answer {
  NoulA(Double)
  ChoiceA(String, Double, Map[String, Double])
  ScoreA(Double, Double, Map[String, String], Map[String, Double])
  BoxA(BoxCoords, Double?)
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
