module Request = struct
  type 'a t = { node       : string
              ; request_id : string
              ; payload    : 'a
              }
end

module Response = struct
  type 'a t = { request_id : string
              ; payload    : 'a
              }
end

module Msg = struct
  type 'elt t =
    | Resp_append_entries of (Scow_term.t * bool) Response.t
    | Resp_request_vote   of (Scow_term.t * bool) Response.t
    | Request_vote        of Scow_rpc.Request_vote.t Request.t
    | Append_entries      of 'elt Scow_rpc.Append_entries.t Request.t
end

module type S = sig
  type elt

  val to_string : elt Msg.t -> string
  val of_string : string -> elt Msg.t option
end
