(** Database interface to the Ocsimore database. *)

module Lwt_PGOCaml : PGOCaml_generic.PGOCAML_GENERIC
  with type 'a monad = 'a Lwt.t
module Lwt_Query : Query.QUERY
  with type 'a Db.t = 'a Lwt_PGOCaml.t and type 'a Db.monad = 'a Lwt.t

type db_t = Lwt_PGOCaml.pa_pg_data Lwt_PGOCaml.t

val pool : db_t Lwt_pool.t

(** Perform an atomic transaction (using BEGIN and COMMIT/ROLLBACK *)
val transaction_block : db_t -> (unit -> 'a Lwt.t) -> 'a Lwt.t

(** Same as [transaction_block] but takes a db connection in the pool. *)
val full_transaction_block : (db_t -> 'a Lwt.t) -> 'a Lwt.t

val view : ('a, 'b) Sql.view -> 'a list Lwt.t

val view_one : ('a, 'b) Sql.view -> 'a Lwt.t

val view_opt : ('a, 'b) Sql.view -> 'a option Lwt.t

val query : unit Sql.query -> unit Lwt.t

val value :
  < nul : Sql.non_nullable; t : 'a #Sql.type_info; .. > Sql.t ->
  'a Lwt.t
