open Core.Std
open Async.Std

module Stream_node = Scow_transport_stream_server.Node

module Elt = struct
  type t = int
  let compare = Int.compare
  let to_string = Int.to_string
  let of_string = Int.of_string
end

module Statem = struct
  type op = Elt.t
  type ret = unit
  type t = Int.Set.t ref

  let create () = ref Int.Set.empty

  let apply t op =
    t := Set.add !t op;
    Deferred.unit
end

module Simple_codec = struct
  type elt = Elt.t

  module Msg = Scow_transport_stream_codec.Msg

  let to_string = function
    | Msg.Resp_append_entries (request_id_str, term, success) ->
      sprintf "resp_append_entries!%s!%d!%s"
        request_id_str
        (Scow_term.to_int term)
        (Bool.to_string success)
    | Msg.Resp_request_vote (request_id_str, term, granted) ->
      sprintf "resp_request_vote!%s!%d!%s"
        request_id_str
        (Scow_term.to_int term)
        (Bool.to_string granted)
    | Msg.Request_vote (node_str, request_id_str, request_vote) ->
      let module Rv = Scow_rpc.Request_vote in
      sprintf "request_vote!%s!%s!%d!%d!%d"
        node_str
        request_id_str
        (Scow_term.to_int request_vote.Rv.term)
        (Scow_log_index.to_int request_vote.Rv.last_log_index)
        (Scow_term.to_int request_vote.Rv.last_log_term)
    | Msg.Append_entries (node_str, request_id_str, append_entries) ->
      let module Ae = Scow_rpc.Append_entries in
      sprintf "append_entries!%s!%s!%d!%d!%d!%d!%s"
        node_str
        request_id_str
        (Scow_term.to_int append_entries.Ae.term)
        (Scow_log_index.to_int append_entries.Ae.prev_log_index)
        (Scow_term.to_int append_entries.Ae.prev_log_term)
        (Scow_log_index.to_int append_entries.Ae.leader_commit)
        (String.concat ~sep:","
           (List.map
              ~f:(fun (term, elt) ->
                sprintf "%d;%d" (Scow_term.to_int term) elt)
              append_entries.Ae.entries))

  let of_string str =
    let msg =
      match String.split ~on:'!' str with
        | [ "resp_append_entries"
          ; request_id_str
          ; term_str
          ; success_str
          ] ->
          let term = Option.value_exn (Scow_term.of_int (Int.of_string term_str)) in
          let success = Bool.of_string success_str in
          Msg.Resp_append_entries (request_id_str, term, success)
        | [ "resp_request_vote"
          ; request_id_str
          ; term_str
          ; granted_str
          ] ->
          let term = Option.value_exn (Scow_term.of_int (Int.of_string term_str)) in
          let granted = Bool.of_string granted_str in
          Msg.Resp_request_vote (request_id_str, term, granted)
        | [ "request_vote"
          ; node_str
          ; request_id_str
          ; term_str
          ; last_log_index_str
          ; last_log_term_str
          ] ->
          let term = Option.value_exn (Scow_term.of_int (Int.of_string term_str)) in
          let last_log_index =
            Option.value_exn (Scow_log_index.of_int (Int.of_string last_log_index_str))
          in
          let last_log_term =
            Option.value_exn (Scow_term.of_int (Int.of_string last_log_term_str))
          in
          let module Rv = Scow_rpc.Request_vote in
          let request_vote = { Rv.term
                             ;    last_log_index
                             ;    last_log_term
                             }
          in
          Msg.Request_vote (node_str, request_id_str, request_vote)
        | [ "append_entries"
          ; node_str
          ; request_id_str
          ; term_str
          ; prev_log_index_str
          ; prev_log_term_str
          ; leader_commit_str
          ; entries_str
          ] -> begin
          let term = Option.value_exn (Scow_term.of_int (Int.of_string term_str)) in
          let prev_log_index =
            Option.value_exn (Scow_log_index.of_int (Int.of_string prev_log_index_str))
          in
          let prev_log_term =
            Option.value_exn (Scow_term.of_int (Int.of_string prev_log_term_str))
          in
          let leader_commit =
            Option.value_exn (Scow_log_index.of_int (Int.of_string leader_commit_str))
          in
          let entries =
            entries_str
            |> String.split ~on:','
            |> List.filter ~f:((<>) "")
            |> List.map ~f:(String.lsplit2_exn ~on:';')
            |> List.map
                ~f:(fun (term_str, elt_str) ->
                  let term = Option.value_exn (Scow_term.of_int (Int.of_string term_str)) in
                  (term, Int.of_string elt_str))
          in
          let module Ae = Scow_rpc.Append_entries in
          let append_entries = { Ae.term
                               ;    prev_log_index
                               ;    prev_log_term
                               ;    leader_commit
                               ;    entries
                               }
          in
          Msg.Append_entries (node_str, request_id_str, append_entries)
        end
        | _ -> failwith str
    in
    Some msg
end

module Log = Scow_log_memory.Make(Elt)
module Stream_transport = Scow_transport_stream.Make(Simple_codec)
module Timeout_transport = Scow_transport_timeout.Make(Stream_transport)
module Transport = Scow_transport_party.Make(Timeout_transport)
module Store = Scow_store_memory.Make(Transport.Node)

module Scow = Scow.Make(Statem)(Log)(Store)(Transport)

module Scow_inst = struct
  type t = { scow   : Scow.t
           ; statem : Statem.t
           }
end

let start_transport me =
  Stream_transport.start ~me
  >>= function
    | Ok transport -> Deferred.return transport
    | Error _      -> failwith "nyi"

let create_scow nodes me =
  start_transport me
  >>= fun stream_transport ->
  let timeout_transport = Timeout_transport.create (sec 1.) stream_transport in
  let transport =
    Transport.create
      (Int.of_string Sys.argv.(2))
      (sec (Float.of_string Sys.argv.(3)))
      me
      timeout_transport
  in
  let log = Log.create () in
  let store = Store.create () in
  let statem = Statem.create () in
  let module Ia = Scow.Init_args in
  let init_args = { Ia.me           = me
                  ;    nodes        = nodes
                  ;    statem       = statem
                  ;    transport    = transport
                  ;    log          = log
                  ;    store        = store
                  ;    timeout      = sec 1.0
                  ;    timeout_rand = sec 2.0
                  }
  in
  Scow.start init_args
  >>= function
    | Ok scow -> Deferred.return Scow_inst.({scow; statem})
    | Error _ -> failwith "nyi"

let string_of_statem statem =
  String.concat
    ~sep:", "
    (List.map ~f:Int.to_string (List.sort ~cmp:Int.compare (Set.to_list !statem)))

let print_statem_info scow_insts () =
  let print scow_inst =
    Scow.me scow_inst.Scow_inst.scow
    >>=? fun me ->
    Scow.leader scow_inst.Scow_inst.scow
    >>=? fun leader_opt ->
    let leader =
      Option.value
        (Option.map ~f:Stream_transport.Node.to_string leader_opt) ~default:"Unknown"
    in
    printf "%s: %s [%s]\n%!"
      (Transport.Node.to_string me)
      leader
      (string_of_statem scow_inst.Scow_inst.statem);
    Deferred.return (Ok ())
  in
  Deferred.List.iter
    ~f:(fun scow_inst ->
      print scow_inst
      >>= fun _ ->
      Deferred.unit)
    scow_insts
  >>= fun _ ->
  printf "---\n";
  Deferred.unit

let append_entry next_val scow_insts () =
  let print scow_inst =
    Scow.me scow_inst.Scow_inst.scow
    >>=? fun me ->
    Scow.append_log
      scow_inst.Scow_inst.scow
      !next_val
  in
  incr next_val;
  Deferred.List.iter
    ~f:(fun scow_inst ->
      print scow_inst
      >>= fun _ ->
      Deferred.unit)
    scow_insts

let rec create_nodes = function
  | 0 -> []
  | n ->
    let node_opt = Stream_node.create ~host:"localhost" ~port:(9000 + n) in
    Option.value_exn node_opt :: create_nodes (n - 1)

let main () =
  let nodes  = create_nodes (Int.of_string Sys.argv.(1)) in
  Deferred.List.map
    ~f:(create_scow nodes)
    nodes
  >>| fun scow_insts ->
  every
    (sec 5.0)
    (Fn.compose ignore (print_statem_info scow_insts));
  after (sec 5.0)
  >>| fun () ->
  every
    (sec 3.0)
    (Fn.compose ignore (append_entry (ref 0) scow_insts))

let () =
  Random.self_init ();
  ignore (main ());
  never_returns (Scheduler.go ());
