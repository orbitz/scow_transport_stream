open Core.Std
open Async.Std

module Inet = Async_extra.Import.Socket.Address.Inet

module Node = struct
  type t = (string * int) with compare

  let create ~host ~port =
    Some (host, port)

  let to_string (host, port) =
    sprintf "%s:%d" host port

  let of_string s =
    Option.try_with
      (fun () ->
        let (host, port_str) = String.lsplit2_exn ~on:':' s in
        (host, Int.of_string port_str))

  let host (host, _) = host
  let port (_, port) = port
end

type t = { server : (Inet.t, int) Tcp.Server.t
         ; w      : string Pipe.Writer.t
         ; r      : string Pipe.Reader.t
         }

let rec read_until_newline reader =
  Pipe.read reader
  >>= function
    | `Ok data -> begin
      match String.lsplit2 ~on:'\n' data with
        | Some lr ->
          Deferred.return (Ok lr)
        | None -> begin
          read_until_newline reader
          >>=? fun (left, right) ->
          Deferred.return (Ok (data ^ left, right))
        end
    end
    | `Eof ->
      Deferred.return (Error `No_newline)

let read_length reader =
  read_until_newline reader
  >>=? fun (length_str, rest) ->
  Deferred.return (Ok (Int.of_string length_str, rest))

let rec read_data reader = function
  | 0 -> Deferred.return (Ok "")
  | n -> begin
    Pipe.read reader
    >>= function
      | `Ok data -> begin
        read_data reader (n - String.length data)
        >>=? fun rest ->
        Deferred.return (Ok (data ^ rest))
      end
      | `Eof ->
        Deferred.return (Error `Truncated)
  end

let do_handler w reader =
  read_length reader
  >>=? fun (length, rest) ->
  read_data reader (length - String.length rest)
  >>=? fun data ->
  Pipe.write w (rest ^ data)
  >>= fun () ->
  Deferred.return (Ok ())

let handler w _socket reader _writer =
  do_handler w (Reader.pipe reader)
  >>= fun _ ->
  Deferred.unit

let start ~port =
  let (r, w) = Pipe.create () in
  Tcp.Server.create
    (Tcp.on_port port)
    (handler w)
  >>= fun server ->
  let t = { server; r; w } in
  Deferred.return (Ok t)

let stop t =
  Pipe.close t.w;
  Tcp.Server.close t.server
  >>= fun () ->
  Deferred.return (Ok ())

let send t node data =
  let host_port =
    Tcp.to_host_and_port
      (Node.host node)
      (Node.port node)
  in
  Monitor.try_with
    (fun () ->
      Tcp.with_connection host_port
        (fun _socket _reader writer ->
          Writer.write writer (sprintf "%d\n" (String.length data));
          Writer.write writer data;
          Deferred.unit))
  >>= function
    | Ok ()   -> Deferred.return (Ok ())
    | Error _ -> Deferred.return (Error `Transport_error)

let reader t = t.r

