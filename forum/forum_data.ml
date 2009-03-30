(* Ocsimore
 * Copyright (C) 2009
 * Laboratoire PPS - Université Paris Diderot - CNRS
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
(**
   @author Vincent Balat
   @author Boris Yakobowski
*)


let (>>=) = Lwt.bind

open Forum

(** {2 Database access with verification of permissions} *)

let new_forum ~sp ~sd ~title ~descr ?arborescent () =
  Users.get_user_data sp sd >>= fun u ->
  Users.in_group ~sp ~sd ~user:u.Users.id
    ~group:Forum.forum_creators.Users.id ()
  >>= fun b ->
  if b
  then Forum_sql.new_forum ~title ~descr ?arborescent ()
  else Lwt.fail Ocsimore_common.Permission_denied

let new_message ~sp ~sd ~forum_id ~author_id
    ?subject ?parent_id ?sticky ~text = 
  Forum.get_role sp sd forum_id >>= fun role ->
  let first_msg = parent_id = None in
  if (first_msg && role.message_writers)
    || (not first_msg && role.comment_writers)
  then 
    let moderated =
      (first_msg && (role.message_moderators || role.message_writers_notmod))
      || (not first_msg && 
            (role.comment_moderators || role.comment_writers_notmod))
    in
    Forum_sql.new_message ~forum_id ~author_id
      ?subject ?parent_id ~moderated ?sticky ~text
  else Lwt.fail Ocsimore_common.Permission_denied

let set_deleted ~sp ~sd ~message_id ~deleted =
  Forum_sql.get_message ~message_id
  >>= fun (_, _, _, _, parent_id, _, forum_id, _, _, _, _) ->
  Forum.get_role sp sd forum_id >>= fun role ->
  let first_msg = parent_id = None in
  if ((first_msg && role.message_deletors)
      || (not first_msg && role.comment_deletors))
  then Forum_sql.set_deleted ~message_id ~deleted
  else Lwt.fail Ocsimore_common.Permission_denied

let set_moderated ~sp ~sd ~message_id ~moderated =
  Forum_sql.get_message ~message_id
  >>= fun (_, _, _, _, parent_id, _, forum_id, _, _, _, _) ->
  Forum.get_role sp sd forum_id >>= fun role ->
  let first_msg = parent_id = None in
  if ((first_msg && role.message_moderators)
      || (not first_msg && role.comment_moderators))
  then Forum_sql.set_moderated ~message_id ~moderated
  else Lwt.fail Ocsimore_common.Permission_denied

let set_sticky ~sp ~sd ~message_id ~sticky =
  Forum_sql.get_message ~message_id
  >>= fun (_, _, _, _, parent_id, _, forum_id, _, _, _, _) ->
  Forum.get_role sp sd forum_id >>= fun role ->
  let first_msg = parent_id = None in
  if ((first_msg && role.message_sticky_setters)
      || (not first_msg && role.comment_sticky_setters))
  then Forum_sql.set_sticky ~message_id ~sticky
  else Lwt.fail Ocsimore_common.Permission_denied

let find_forum ~sp ~sd ?forum_id ?title () =
  Forum_sql.find_forum ?forum_id ?title () 
  >>= fun ((i, _, _, _, _, _) as f) ->
  Users.get_user_data sp sd >>= fun u ->
  let u = u.Users.id in
  Forum.forum_visible_group i >>= fun g ->
  Users.in_group ~sp ~sd ~user:u ~group:g ()
  >>= fun b ->
  if b
  then Lwt.return f
  else Lwt.fail Ocsimore_common.Permission_denied

let get_forums_list ~sp ~sd () =
  Users.get_user_data sp sd >>= fun u ->
  let u = u.Users.id in
  Forum_sql.get_forums_list () >>= fun l ->
  Ocsimore_lib.lwt_filter
    (fun (i, _, _, _, _, _) ->
       Forum.forum_visible_group i >>= fun g ->
       Users.in_group ~sp ~sd ~user:u ~group:g ())
    l

let get_message ~sp ~sd ~message_id =
  Forum_sql.get_message ~message_id
  >>= fun ((_, _, _, _, parent_id, _, forum_id, _, _, _, _) as msg) ->
  Forum.get_role sp sd forum_id >>= fun role ->
  let first_msg = parent_id = None in
  if ((first_msg && role.message_readers)
      || (not first_msg && role.comment_readers))
  then Lwt.return msg
  else Lwt.fail Ocsimore_common.Permission_denied

let get_thread ~sp ~sd ~message_id =
  Forum_sql.get_thread ~message_id
  >>= function
    | [] -> Lwt.return []
    | (((_, _, _, _, parent_id, _, forum_id, _, _, _, _) as msg)::l) as th ->
        Forum.get_role sp sd forum_id >>= fun role ->
        let first_msg = parent_id = None in
        if (first_msg && role.message_readers)
        then (if role.comment_readers
              then Lwt.return th
              else Lwt.return [msg])
        else (if (not first_msg && role.comment_readers)
              then Lwt.return th
              else Lwt.fail Ocsimore_common.Permission_denied)
