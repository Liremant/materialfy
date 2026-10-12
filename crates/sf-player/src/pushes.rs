//! JSON pushes of the session's dealer for the layers above sf-player, which do not depend on librespot-core.
//! A subscription made before Spirc launches the dealer waits for it; one made later joins the running dealer.
use futures::StreamExt;
use futures::stream::BoxStream;
use librespot_core::dealer::protocol::PayloadValue;

use crate::Session;

/// Text of every JSON push whose URI starts with `uri` (e.g. "social-connect/v2/session_update"). Raw (protobuf)
/// pushes are skipped. The stream ends with the session's dealer.
pub fn listen_json(session: &Session, uri: &str) -> Result<BoxStream<'static, String>, String> {
    let stream = session.dealer().listen_for(uri, Ok).map_err(|error| error.to_string())?;
    Ok(stream
        .filter_map(|message| async move {
            match message.ok()?.payload {
                PayloadValue::Json(text) => Some(text),
                PayloadValue::Raw(bytes) => String::from_utf8(bytes).ok().filter(|text| text.trim_start().starts_with('{')),
                _ => None,
            }
        })
        .boxed())
}
