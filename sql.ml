(* Ocsimore
 * Copyright (C) 2005 Piero Furiesi Jaap Boender Vincent Balat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

(** PostgreSQL database operations via PGOCaml library. *)

module PGOCaml =
  PGOCaml_generic.Make (struct include Lwt include Lwt_chan end)

open Lwt
open Ocsimore_lib
open CalendarLib

(* let db = PGOCaml.connect ~host:"courbet.kerguelen.org" ~database:"ocsimore" ~user:"ocsigen" () *)

type db_t = (string, bool) Hashtbl.t PGOCaml.t

let connect () =
  PGOCaml.connect
    ~database:"ocsimore" 
    ~user:Ocsimore_config.user
    ~password:!Ocsimore_config.password ()


(*
  type db_int_t = int32;;
  type db_size_t = int64;;
  type db_count_t = int64;;
*)

let pool = Lwt_pool.create 40 connect
  
type db_offset_t = int64;;

let db_offset_of_int = Int64.of_int 

let transaction_block db f =
  PGOCaml.begin_work db >>= fun _ -> 
  Lwt.catch
    (fun () ->
print_endline "SQL transaction";
       f () >>= fun r ->
       PGOCaml.commit db >>= fun () -> 
       Lwt.return r)
    (fun e -> 
       PGOCaml.rollback db >>= fun () ->
       Lwt.fail e)
  
let full_transaction_block f =
  Lwt_pool.use pool (fun db -> transaction_block db (fun () -> f db))
  



(*
  (* SQL aggregate functions can sometimes return NULL values, but
     this is not the case for COUNT, that _always_ returns a non-NULL
     value. PGOCaml's nullability test fails here, as the type
     inferred for PGSQL(db) "SELECT COUNT(field) FROM YourTable" is
     'int64 option' and not 'int64', as expected. *)

(* SERVICES *)
(*VVV Jaap - PAS FINI !!!!!!!!!!!!!!! *)
let new_service db ~url =
  (* inserts a new service *)
  begin_work db >>=remove this! use full_transaction_block
  fun _ -> PGSQL(db) "INSERT INTO services (url) \
                VALUES ($url)" >>=
        fun () -> serial4 db "services_id_seq" >>=
        fun srv_id -> commit db >>=
        fun _ -> return srv_id;;

let list_services db =
        begin_work db >>=remove this! use full_transaction_block
        fun _ -> PGSQL(db) "SELECT url FROM services" >>=
        fun srv_l -> commit db >>=
        fun _ -> return srv_l;;

let get_service_parameters db ~url =
        begin_work db >>=remove this! use full_transaction_block
        fun _ -> PGSQL(db) "SELECT id FROM services WHERE url = $url" >>=
        fun x -> (match x with [id] -> return id | _ -> fail Not_found) >>=
        fun id -> PGSQL(db) "SELECT id, name FROM service_parameters \
                WHERE service_id = $id" >>=
        fun param_l -> commit db >>=
        fun _ -> return param_l;;

let add_parameter_to_service db ~url ~param_name =
        begin_work db >>=remove this! use full_transaction_block
        fun _ -> PGSQL(db) "SELECT id FROM services WHERE url = $url" >>=
        fun x -> (match x with [id] -> return id | _ -> fail Not_found) >>=
        fun id -> PGSQL(db) "INSERT INTO service_parameters \
                (service_id, name) VALUES \
                ($id, $param_name)"  >>=
        fun () -> serial4 db "service_parameters_id_seq" >>=
        fun param_id -> commit db >>=
        fun _ -> return param_id;;
*)
