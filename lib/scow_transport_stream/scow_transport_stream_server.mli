open Async.Std

type t

module Node : sig
  type t

  val create : host:string -> port:int -> t option

  val compare   : t -> t -> int
  val to_string : t -> string
  val of_string : string -> t option
  val host      : t -> string
  val port      : t -> int
end

val start : port:int -> (t, [> `Transport_error ]) Deferred.Result.t
val stop  : t -> (unit, [> `Transport_error ]) Deferred.Result.t

val send   : t -> Node.t -> string -> (unit, [> `Transport_error ]) Deferred.Result.t
val reader : t -> string Pipe.Reader.t
