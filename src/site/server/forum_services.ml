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

let ( ** ) = Eliom_parameter.prod
let ( >>= ) = Lwt.bind

open User_sql.Types

let forum_action_eref = Eliom_reference.eref ~scope:Eliom_common.request_scope None

let set_forum_action action =
  Eliom_reference.set forum_action_eref (Some action)

let register_services () =
  let add_message_service =
    Eliom_service.Http.post_coservice'
      ~keep_get_na_params:false
      ~name:"forum_add"
      ~post_params:
      (Eliom_parameter.string "actionname" **
         ((Eliom_parameter.sum
             (Forum.eliom_message "parent")
             (Forum.eliom_forum "forum")) **
            (Eliom_parameter.opt (Eliom_parameter.string "subject") **
               Eliom_parameter.string "content")))
      ()
  in

  Eliom_registration.Any.register
    ~service:add_message_service
    (fun () (actionname, (parent, (subject, text))) ->
      lwt (forum, parent_id) =
        match parent with
         | Eliom_parameter.Inj2 forum -> (* new messages *)
             Lwt.return (forum, None)
         | Eliom_parameter.Inj1 parent_id -> (* comment *)
             (* We do not require the user to be allowed to read the message ...
                (Forum_sql.get_message and not Forum_data.get_message) *)
             Forum_sql.get_message ~message_id:parent_id () >>= fun m ->
             Lwt.return (m.Forum_types.m_forum, Some parent_id)
      in
      lwt _role = Forum.get_role forum in (* VVV : why is role not used here ? *)
      if actionname = "save" then
        try_lwt
          lwt u = User.get_user_data () in
          lwt _ =
            Forum_data.new_message
              ~forum ~creator_id:u.user_id ?subject ?parent_id ~text ()
          in
          Eliom_registration.Redirection.send
            Eliom_service.void_hidden_coservice'
        with Ocsimore_common.Permission_denied ->
          lwt () =
            set_forum_action (Forum.Msg_creation_not_allowed (forum, parent_id))
          in
          Eliom_registration.Action.send ()
      else (* preview *)
        lwt () =
          set_forum_action (Forum.Preview ((forum, parent_id), text))
        in
        Eliom_registration.Action.send ());

  (* Moderation *)
  let moderate_message_service =
    Eliom_service.Http.post_coservice'
      ~keep_get_na_params:false
      ~name:"forum_moderate"
      ~post_params:(Forum.eliom_message "msg")
      ()
  in

  Eliom_registration.Action.register
    ~service:moderate_message_service
    (fun () msg ->
       Forum_data.set_moderated ~message_id:msg ~moderated:true);

(* AEFF
  (* Deletion *)
  let delete_message_service =
    Eliom_service.new_post_coservice'
      ~keep_get_na_params:false
      ~name:"forum_delete_message"
      ~post_params:(Forum.eliom_message "msg")
      ()
  in

  Eliom_predefmod.Action.register
    ~service:delete_message_service
    (fun sp () msg ->
       Forum_data.set_deleted ~sp ~message_id:msg ~deleted:true
    );
*)

  (** Atom feed services *)
  let thread_feed_service = Eliom_service.Http.service
    ~path:["thread_feed"]
    ~get_params:(Forum.eliom_message "message") () in

  let forum_feed_service = Eliom_service.Http.service
    ~path:["forum_feed"]
    ~get_params:(Forum.eliom_forum "forum") () in
  { Forum_types.add_message_service; moderate_message_service; thread_feed_service; forum_feed_service }

let path_edit_forum = [!Ocsimore_config.admin_dir;"edit_forum"]
let path_create_forum = [!Ocsimore_config.admin_dir;"create_forum"]

let edit_forum = Eliom_service.App.service
  ~path:path_edit_forum
  ~get_params:(Forum.eliom_forum "forum") ()

let create_forum = Eliom_service.App.service
  ~path:path_create_forum
  ~get_params:Eliom_parameter.unit ()

let view_forums = Eliom_service.Http.service
  ~path:[!Ocsimore_config.admin_dir;"view_forums"]
  ~get_params:Eliom_parameter.unit ()
