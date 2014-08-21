open Async.Std

module Make : functor (Codec : Scow_transport_stream_codec.S) -> sig
  type t
  type ctx
  type elt = Codec.elt

  module Node : sig
    type t = Scow_transport_stream_server.Node.t
    val compare   : t -> t -> int
    val to_string : t -> string
  end

  val start : me:Node.t -> (t, [> `Transport_error ]) Deferred.Result.t
  val stop  : t -> (unit, [> `Transport_error ]) Deferred.Result.t

  val listen :
    t ->
    (((Node.t, Codec.elt) Scow_transport.Msg.t * ctx), [> `Transport_error ]) Deferred.Result.t

  val resp_append_entries :
    t ->
    ctx ->
    term:Scow_term.t ->
    success:bool ->
    (unit, [> `Transport_error ]) Deferred.Result.t

  val resp_request_vote :
    t ->
    ctx ->
    term:Scow_term.t ->
    granted:bool ->
    (unit, [> `Transport_error ]) Deferred.Result.t

  val request_vote :
    t ->
    Node.t ->
    Scow_rpc.Request_vote.t ->
    ((Scow_term.t * bool), [> `Transport_error ]) Deferred.Result.t

  val append_entries :
    t ->
    Node.t ->
    Codec.elt Scow_rpc.Append_entries.t ->
    ((Scow_term.t * bool), [> `Transport_error ]) Deferred.Result.t
end
