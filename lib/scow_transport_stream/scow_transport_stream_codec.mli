module Msg : sig
  type 'elt t =
    | Resp_append_entries of (string * Scow_term.t * bool)
    | Resp_request_vote   of (string * Scow_term.t * bool)
    | Request_vote        of (string * string * Scow_rpc.Request_vote.t)
    | Append_entries      of (string * string * 'elt Scow_rpc.Append_entries.t)
end

module type S = sig
  type elt

  val to_string : elt Msg.t -> string
  val of_string : string -> elt Msg.t option
end
