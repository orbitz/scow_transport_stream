open Core.Std
open Async.Std

module Stream_codec = Scow_transport_stream_codec

module Request_map = Int.Map

module Make = functor (Codec : Stream_codec.S) -> struct
  module Node = struct
    include Scow_transport_stream_server.Node
  end

  type t = { server                  : Scow_transport_stream_server.t
           ; me                      : Node.t
           ; mutable next_request_id : int
           ; mutable append_entries  : (Scow_term.t * bool) Ivar.t Request_map.t
           ; mutable request_votes   : (Scow_term.t * bool) Ivar.t Request_map.t
           }

  type ctx = (Node.t * int)
  type elt = Codec.elt

  let start ~me =
    Scow_transport_stream_server.start ~port:(Node.port me)
    >>=? fun server ->
    let t = { server          = server
            ; me              = me
            ; next_request_id = 0
            ; append_entries  = Request_map.empty
            ; request_votes   = Request_map.empty
            }
    in
    Deferred.return (Ok t)

  let stop t =
    Scow_transport_stream_server.stop t.server

  let rec listen t =
    let reader = Scow_transport_stream_server.reader t.server in
    Pipe.read reader
    >>= function
      | `Ok data -> begin
        match Codec.of_string data with
          | Some msg -> handle_msg t msg
          | None     -> listen t
      end
      | `Eof -> Deferred.return (Error `Transport_error)
  and handle_msg t = function
    | Stream_codec.Msg.Request_vote request ->
      handle_request_vote t request
    | Stream_codec.Msg.Append_entries request ->
      handle_append_entries t request
    | Stream_codec.Msg.Resp_append_entries response ->
      handle_resp_append_entries t response
    | Stream_codec.Msg.Resp_request_vote response ->
      handle_resp_request_vote t response
  and handle_request_vote t request =
    let module R   = Stream_codec.Request in
    let node       = Option.value_exn (Node.of_string request.R.node) in
    let request_id = Int.of_string request.R.request_id in
    let ctx        = (node, request_id) in
    let result     =
      Scow_transport.Msg.Request_vote (node, request.R.payload)
    in
    Deferred.return (Ok (result, ctx))
  and handle_append_entries t request =
    let module R   = Stream_codec.Request in
    let node       = Option.value_exn (Node.of_string request.R.node) in
    let request_id = Int.of_string request.R.request_id in
    let ctx        = (node, request_id) in
    let result     =
      Scow_transport.Msg.Append_entries (node, request.R.payload)
    in
    Deferred.return (Ok (result, ctx))
  and handle_resp_append_entries t response =
    let module R       = Stream_codec.Response in
    let request_id     = Int.of_string response.R.request_id in
    let ret            = Map.find_exn t.append_entries request_id in
    let append_entries = Map.remove t.append_entries request_id in
    t.append_entries <- append_entries;
    Ivar.fill ret response.R.payload;
    listen t
  and handle_resp_request_vote t response =
    let module R      = Stream_codec.Response in
    let request_id    = Int.of_string response.R.request_id in
    let ret           = Map.find_exn t.request_votes request_id in
    let request_votes = Map.remove t.request_votes request_id in
    t.request_votes <- request_votes;
    Ivar.fill ret response.R.payload;
    listen t

  let resp_append_entries t (node, request_id) ~term ~success =
    let module R = Stream_codec.Response in
    let response = { R.request_id = Int.to_string request_id
                   ;   payload    = (term, success)
                   }
    in
    let response =
      Codec.to_string
        (Stream_codec.Msg.Resp_append_entries response)
    in
    Scow_transport_stream_server.send
      t.server
      node
      response

  let resp_request_vote t (node, request_id) ~term ~granted =
    let module R = Stream_codec.Response in
    let response = { R.request_id = Int.to_string request_id
                   ;   payload    = (term, granted)
                   }
    in
    let response =
      Codec.to_string
        (Stream_codec.Msg.Resp_request_vote response)
    in
    Scow_transport_stream_server.send
      t.server
      node
      response

  let request_vote t node request_vote =
    let request_id     = t.next_request_id in
    let ret            = Ivar.create () in
    let request_votes  = Map.add ~key:request_id ~data:ret t.request_votes in
    let module R       = Stream_codec.Request in
    let request        = { R.node       = Node.to_string t.me
                         ;   request_id = Int.to_string request_id
                         ;   payload    = request_vote
                         }
    in
    let request =
      Codec.to_string
        (Stream_codec.Msg.Request_vote request)
    in
    t.next_request_id <- request_id + 1;
    t.request_votes <- request_votes;
    Scow_transport_stream_server.send
      t.server
      node
      request
    >>=? fun () ->
    Ivar.read ret
    >>= fun result ->
    Deferred.return (Ok result)

  let append_entries t node append_entries =
    let request_id         = t.next_request_id in
    let ret                = Ivar.create () in
    let append_entries_map = Map.add ~key:request_id ~data:ret t.append_entries in
    let module R           = Stream_codec.Request in
    let request            = { R.node       = Node.to_string t.me
                             ;   request_id = Int.to_string request_id
                             ;   payload    = append_entries
                             }
    in
    let request =
      Codec.to_string
        (Stream_codec.Msg.Append_entries request)
    in
    t.next_request_id <- request_id + 1;
    t.append_entries <- append_entries_map;
    Scow_transport_stream_server.send
      t.server
      node
      request
    >>=? fun () ->
    Ivar.read ret
    >>= fun result ->
    Deferred.return (Ok result)
end
