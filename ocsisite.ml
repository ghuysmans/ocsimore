(* Ocsimore
 * http://www.ocsigen.org
 * Copyright (C) 2008-2009
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

(**
   @author Vincent Balat
   @author Boris Yakobowski
*)

open Lwt
open User_sql.Types
open Wiki_types

let ( ** ) = Eliom_parameters.prod

(** Options for Ocsisite *)

let admin_staticdir =
  let rec find_wikidata (_staticadm as data) = function
    | [] -> Lwt.return data

    | (Simplexmlparser.Element ("admin", ["staticdir",path], []))::l ->
        find_wikidata (Some path) l

    | _ ->
        Lwt.fail (Ocsigen_extensions.Error_in_config_file
                       ("Unexpected content inside Ocsisite config"))
  in
  let c = Eliom_sessions.get_config () in
  Lwt_unix.run (find_wikidata None c)

exception No_admin_staticdir

let () =
  match admin_staticdir with
    | Some _ -> ()
    | None -> Ocsigen_messages.errlog "Ocsisite: please supply a path for the css and images of the Ocsimore administration wiki.\n  Syntax: <admin staticdir=\"path\" />";
        raise No_admin_staticdir



let error_box = new Wiki_widgets.wikibox_error_box
let wiki_rights = new Wiki.wiki_rights

(** We are at eliom registration time, we can create the services *)
let (
    action_edit_css,
    action_edit_wikibox,
    action_delete_wikibox,
    action_edit_wikibox_permissions,
    action_edit_wiki_permissions,
    action_wikibox_history,
    action_css_history,
    action_old_wikibox,
    action_old_wikiboxcss,
    action_src_wikibox,
    action_send_wikiboxtext,
    action_send_css,
    action_send_wiki_permissions,
    action_send_wikibox_permissions,
    pagecss_service,
    action_create_page,
    action_create_css,
    edit_wiki,
    view_wikis
  ) as wiki_services
    = Wiki_services.make_services ()

let wikibox_widget = new Wiki_widgets.dynamic_wikibox error_box wiki_services

(** We create the default wiki model, called "wikicreole" *)
let wikicreole_model =
  Wiki_models.register_wiki_model
    ~name:"wikicreole"
    ~content_type:Wiki_syntax.wikicreole_content_type
    ~rights:wiki_rights
    ~widgets:wikibox_widget

let () =
  Wiki_ext.register_wikibox_syntax_extensions
    Wiki_syntax.wikicreole_parser error_box


(** We register auxiliary services for administration boxes *)

let service_edit_wikibox = Eliom_services.new_service
  ~path:[Ocsimore_lib.ocsimore_admin_dir; "wiki_edit"]
  ~get_params:Wiki_services.eliom_wikibox_args ()

let () =
  Eliom_duce.Xhtml.register service_edit_wikibox
    (fun sp wb () ->
       Wiki_sql.wikibox_wiki wb >>= fun w ->
       Wiki_sql.get_wiki_info_by_id w >>= fun wiki_info ->
       let rights = Wiki_models.get_rights wiki_info.wiki_model in
       let wikibox_widget = Wiki_models.get_widgets wiki_info.wiki_model in
       Wiki.default_bi ~sp ~wikibox:wb ~rights >>= fun bi ->
       wikibox_widget#display_interactive_wikibox ~bi ~rows:30 wb
       >>= fun page ->
       wikibox_widget#css_header ~sp ?page:None w
       >>= fun css ->
       Ocsimore_page.html_page ~sp ~css {{ [ page ] }}
    )

(** We register the service that lists all the wikis *)
let () =  Eliom_duce.Xhtml.register view_wikis
    (fun sp () () -> wikibox_widget#display_all_wikis sp)


(** (We create the wiki containing the administration boxes *)
let wiki_admin = Lwt_unix.run
  (Lwt.catch
     (fun () -> Wiki_sql.get_wiki_info_by_name Wiki.wiki_admin_name)
     (function
        | Not_found ->
            Wiki.create_wiki
              ~title:Wiki.wiki_admin_name
              ~descr:"Administration boxes"
              ~path:[Ocsimore_lib.ocsimore_admin_dir]
              ~boxrights:true
              ~author:User.admin
              ~container_text:"= Ocsimore administration\r\n\r\n<<loginbox>>\r\n\r\n<<content>>"
              ~model:wikicreole_model
              ()
            >>= fun wid ->
            Wiki_sql.get_wiki_info_by_id wid
        | e -> Lwt.fail e)
   >>= fun id ->
   (** We update the fields [staticdir] and [pages] for the admin wiki *)
   (match admin_staticdir with
      | None -> Lwt.return ()
      | Some path ->
          Wiki_sql.update_wiki
            ~staticdir:(Some path) ~path:(Some Ocsimore_lib.ocsimore_admin_dir)
            id.wiki_id
   ) >>=fun () ->
   ((** And give reading rights to the wiki itself. (As usual, this can be
        overridden on a per-page basis) *)
     let groups = [
       Wiki.wiki_wikiboxes_grps.grp_reader;
       Wiki.wiki_files_readers;
     ] in
     Lwt_util.iter
       (fun g -> User_sql.add_to_group ~user:(basic_user User.anonymous)
          ~group:(g $ id.wiki_id))
       groups
   ) >>= fun () ->
   Lwt.return id
  )

let wiki_admin_id = wiki_admin.wiki_id


(** This function registers a page inside the administration wiki if it does not
    exists, and returns a function giving the current value of the
    corresponding wikibox *)
let register_named_wikibox ~page ~content ~content_type ~comment =
  Lwt_unix.run(
    Lwt.catch
      (fun () ->
         Wiki_sql.get_wikipage_info ~wiki:wiki_admin_id ~page
         >>= fun _ -> Lwt.return ()
      )
      (function Not_found ->
         Wiki_sql.new_wikibox
           ~wiki:wiki_admin_id ~comment ~content ~content_type
           ~author:User.admin ()
         >>= fun box ->
         Wiki_sql.set_box_for_page ~wiki:wiki_admin_id ~wb:box ~page ()

       | e -> Lwt.fail e)
  );
  (fun () ->
     Wiki_sql.get_wikipage_info ~wiki:wiki_admin_id ~page
     >>= fun { wikipage_wikibox = wb} ->
     Wiki_sql.get_wikibox_data ~wb ()
     >>= function
     | Some (_, _, Some content, _, _, _) ->
         Lwt.return content
     | None | Some (_, _, None, _, _, _) ->
         (* fallback, should not happen if the wikiadmin is not corrupted
         or if the templates are not deleted *)
         Lwt.return content)


(** We create the page for the help on the syntax of the wiki *)
let _ = register_named_wikibox
  ~page:Wiki_widgets_interface.wikisyntax_help_name
  ~content_type:Wiki_syntax.wikicreole_content_type
  ~comment:"Wikisyntax help"
  ~content:"===Wiki syntax===

This wiki is using [[http://www.wikicreole.org|Wikicreole]]'s syntax, with a few extensions.

{{creole_cheat_sheet.png|Wikicreole's syntax}}"


(** We register the existing wikis of the database *)
let () = Lwt_unix.run
  (Wiki_sql.iter_wikis
     (fun { wiki_id = wiki; wiki_pages = path } ->
        (match path with
           | None -> ()
           | Some path ->
               let path = Ocsigen_lib.split '/' path in
               Wiki_services.register_wiki ~rights:wiki_rights ~path ~wiki ()
        );
        Lwt.return ()
     )
  )

(** We can now register the service for static files *)
let () =
  let service = match Wiki_self_services.find_servpage wiki_admin_id with
    | None -> raise Wiki.No_admin_wiki
    | Some service -> service
  in
  Ocsimore_page.set_service_for_static_files service




let str = Ocamlduce.Utf8.make

open Xform.XformLwt
open Ops

let user_from_userlogin user =
  User.get_user_by_name user >>= fun u ->
  if u = basic_user User.nobody && user <> User.nobody_login then
    Lwt.return (Xform.ConvError ("This user does not exists: " ^ user))
  else
    Lwt.return (Xform.Converted u)


let opaque_int32_input_aux ?a s =
  convert (string_input ?a s)
    (fun s ->
       Lwt.return (
         try Xform.Converted (Opaque.int32_t (Int32.of_string s))
         with Failure _ -> Xform.ConvError ("Invalid value " ^ s)
       ))

let opaque_int32_input ?a (i : 'a Opaque.int32_t) :
    (Xform.inline, 'a Opaque.int32_t) Xform.XformLwt.t =
  opaque_int32_input_aux ?a (Int32.to_string (Opaque.t_int32 i))

let opaque_int32_input_opt_aux ?a s =
  convert (string_input ?a s)
    (fun s ->
       Lwt.return (
         if s = "" then
           Xform.Converted None
         else
           try Xform.Converted (Some (Opaque.int32_t (Int32.of_string s)))
           with Failure _ -> Xform.ConvError ("Invalid value " ^ s)
       ))

let opaque_int32_input_opt ?a : 'a Opaque.int32_t option -> (Xform.inline, 'a Opaque.int32_t option) Xform.XformLwt.t = function
  | None -> opaque_int32_input_opt_aux ?a ""
  | Some v -> opaque_int32_input_opt_aux ?a (Int32.to_string (Opaque.t_int32 v))

let path_input ?a path =
  string_input ?a
    (match path with
       | None -> ""
       | Some "" -> "/"
       | Some p -> p)
  |> function
       | "" -> None
       | "/" -> Some ""
       | s -> Some s

let staticdir_input ?a staticdir =
  string_input ?a (match staticdir with None -> "" | Some s -> s)
  |> function "" -> None | s -> Some s

let create_wiki_form ~serv_path:_ ~service ~arg ~sp
      ~title ~descr ~path ~boxrights ~staticdir ~admins ~readers ~container ~css
      ?err_handler cont =
  let page sp _arg error form =
    let title = match error with
      | Xform.NoError -> "Wiki creation"
      | _ -> "Error" in
    Ocsimore_page.html_page ~sp ~title
      {{ [<h1>(str title)
          !{: match error with
              | Xform.ErrorMsg err -> {{[<p>(str err)] }}
              | _ -> {{ [] }}
          :}
          form] }}
  in
    form ~fallback:service ~get_args:arg ~page ~sp ?err_handler
      (p (text "Title: " @+ string_input title +@
          text " (used to identify the wiki in the database) ") @@
       p (text "Description: " @+ string_input descr) @@
       p (text "Link this wiki to an url: " @+ path_input path) @@
       p (text "Authorize special permissions on wikiboxes: " @+
          bool_checkbox boxrights) @@
       p (text "Serve static files from a local directory: " @+
          staticdir_input staticdir) @@
       extensible_list "Add wiki admin" "" admins
         (fun adm ->
            p (text "Admin" @+
               convert (string_input adm) user_from_userlogin)) @@
       extensible_list "Add wiki reader" "" readers
         (fun reader ->
            p (text "Reader" @+
               convert (string_input reader) user_from_userlogin)) @@
       p (text "Container text :" @+ [{{<br>[]}}] @+
          text_area ~cols:80 ~rows:20 container)
       @@
       p (text "Css :" @+ [{{<br>[]}}] @+
          text_area ~cols:80 ~rows:20 css)
       @@
       p (submit_button "Create")
      |> cont)
  >>= fun form ->
  page sp arg Xform.NoError form


let create_wiki =
  let err_handler = function
    | Wiki.Wiki_already_registered_at_path ((_, descr), _) ->
        Some (Printf.sprintf "The wiki '%s' is already registered at this path"
                descr)
    | Wiki.Wiki_with_same_title _ ->
        Some "A wiki with this title already exists"
    | Ocsimore_common.Permission_denied ->
        Some "You do not have sufficient permissions to create wikis"
    | _ -> Some "An unknown error has occurred"
 in
  let path = [Ocsimore_lib.ocsimore_admin_dir;"create_wiki"] in
  let create_wiki = Eliom_services.new_service ~path
      ~get_params:Eliom_parameters.unit () in
  Eliom_duce.Xhtml.register create_wiki
    (fun sp () () ->
       User.get_user_name sp >>= fun u ->
       create_wiki_form ~serv_path:path ~service:create_wiki ~arg:() ~sp
         ~title:"" ~descr:"" ~path:(Some "") ~boxrights:true ~staticdir:None
         ~admins:[u] ~readers:[User.anonymous_login]
         ~container:Wiki.default_container_page ~css:""
         ~err_handler
         (fun (title, (descr, (path, (boxrights, (staticdir, (admins, (readers, (container, (css, _button))))))))) sp ->
            let path = match path with
              | None -> None
              | Some p -> Some (Neturl.split_path p)
            in
            Wiki_data.create_wiki ~sp ~title ~descr ?path ~boxrights ?staticdir
              ~admins ~readers ~wiki_css:css ~container_text:container
              ~model:wikicreole_model ~rights:wiki_rights ()
            >>= fun wid ->
            let link = match path with
              | None -> {{ [] }}
              | Some path ->
                  Wiki_services.register_wiki ~rights:wiki_rights
                    ~sp ~path ~wiki:wid ();
                  match Wiki_self_services.find_servpage wid with
                    | None -> (* should never happen, but this is not
                                 really important *) {{ [] }}
                    | Some service ->
                        let link = Eliom_duce.Xhtml.a
                          ~sp ~service {{ "root page" }} [] in
                        let msg1 = str "you can go the "
                        and msg2 = str " of this wiki." in
                        {{ [<p>[ !msg1 link !msg2 ]] }}
            in
            let title = str "Wiki sucessfully created"
            and msg = str (Printf.sprintf "You have created wiki %s"
                             (string_of_wiki wid)) in
            Ocsimore_page.html_page ~sp
              {{ [<h1>title <p>msg !link] }}
         ));
  create_wiki


let edit_wiki_form ~serv_path:_ ~service ~arg ~sp
      ~(wiki:wiki) ~descr ~path ~boxrights ~staticdir ~(container:wikibox option)
      ?err_handler cont =
  let page sp _arg error form =
    let title = match error with
      | Xform.NoError -> "Wiki edition"
      | _ -> "Error" in
    Ocsimore_page.html_page ~sp ~title
      {{ [<h1>(str title)
          !{: match error with
              | Xform.ErrorMsg err -> {{[<p>(str err)] }}
              | _ -> {{ [] }}
          :}
          form] }}
  in
    form ~fallback:service ~get_args:arg ~page ~sp ?err_handler
      (p (opaque_int32_input ~a:{{ { type="hidden" } }} wiki) @@
       p (text "Description: " @+ string_input descr) @@
       p (text "Link this wiki to an url: " @+ path_input path +@
          [{{<br>[]}}] +@
          text "Changing this option will only take effect after the server \
            is restarted; use '/' for the root URL, or nothing if you do not \
            want to bind the wiki") @@
       p (text "Authorize special permissions on wikiboxes: " @+
          bool_checkbox boxrights) @@
       p (text "Serve static files from a local directory: " @+
          staticdir_input staticdir) @@
       p (text "Container wikibox :" @+ opaque_int32_input_opt container)
       @@
       p (submit_button "Create")
      |> cont)
  >>= fun form ->
  page sp arg Xform.NoError form


let edit_wiki =
  let err_handler = function
    | Ocsimore_common.Permission_denied ->
        Some "You do not have sufficient permissions to edit wikis"
    | _ -> Some "An unknown error has occurred"
  in
  Eliom_duce.Xhtml.register edit_wiki
    (fun sp wiki () ->
       Wiki_sql.get_wiki_info_by_id wiki >>= fun info ->
       let rights = Wiki_models.get_rights info.wiki_model in
       rights#can_admin_wiki sp wiki >>= function
         | true ->
             edit_wiki_form ~serv_path:Wiki_services.path_edit_wiki
               ~service:create_wiki ~arg:() ~sp
               ~wiki ~descr:info.wiki_descr ~path:info.wiki_pages
               ~boxrights:info.wiki_boxrights ~staticdir:info.wiki_staticdir
               ~container:info.wiki_container
               ~err_handler
               (fun (wiki, (descr, (path, (boxrights, (staticdir, (container, _v)))))) sp ->
                  Wiki_sql.get_wiki_info_by_id wiki >>= fun wiki_info ->
                  let rights = Wiki_models.get_rights wiki_info.wiki_model in
                  Wiki_data.update_wiki ~rights ~sp ~descr ~path ~boxrights
                    ~staticdir ~container wiki
                  >>= fun () ->
                  let title = str "Wiki information sucessfully edited" in
                  Ocsimore_page.html_page ~sp {{ [<h1>title ] }}
               )
         | false ->
             Ocsimore_page.html_page sp
               {{ [ <h1>"Insufficient permissions"
                    <p>"You do not have enough rights to edit this wiki" ] }} );
  edit_wiki


(** Administration page *)

let root_page : (Eliom_sessions.server_params -> Xhtmltypes_duce.blocks) ref =
  ref (fun _sp -> {{ [ <h1>"Ocsimore administration page"] }})

let add_to_root_page (arg : Eliom_sessions.server_params -> Xhtmltypes_duce.blocks) =
  let old = !root_page in
  root_page := (fun sp -> {{ {: old sp :} @ (arg sp) }})


let admin_root =
  Eliom_services.new_service
    ~path:[Ocsimore_lib.ocsimore_admin_dir;"root"]
    ~get_params:Eliom_parameters.unit ()

let () = Eliom_duce.Xhtml.register admin_root
  (fun sp () () ->
     Ocsimore_page.html_page sp (!root_page sp))

(* Links for users and wikis *)
let () =
    add_to_root_page (fun sp ->
      let link service text =
        let href = Ocamlduce.Utf8.make
          (Eliom_duce.Xhtml.make_uri ~sp ~service ())
        and text = Ocamlduce.Utf8.make text in
        {{ <a href=href>text }}
      in
      let link_login = link User_site.service_login "Login"
      and link_create_user = match User_site.service_user_creation with
        | None -> {{ [] }}
        | Some service -> {{ [ {: link service "Create a new user" :} <br>[]] }}
      and link_view_groups = link User_site.service_view_groups
        "View and edit groups or users"
      and link_create = link create_wiki "Create a new wiki"
      and link_view_wikis = link view_wikis "View and edit wikis"
      in
      {{ [ <h2>"Users"
           <p>[ link_login <br>[] !link_create_user link_view_groups<br>[] ]

           <h2>"Wikis"
           <p>[ link_create <br>[] link_view_wikis <br>[] ]
         ] }})



(*
(* Code to migrate from old wikibox ids to uids *)
let service_update_wikiboxes_uid = Eliom_services.new_service
  ~path:[Ocsimore_lib.ocsimore_admin_dir; "update"]
  ~get_params:Eliom_parameters.unit ()

let () =
  Eliom_duce.Xhtml.register service_update_wikiboxes_uid
    (fun sp () () ->
       let r = ref 0 in
       let wp = Wiki_models.get_default_wiki_preparser wikicreole_model in
       Wiki_sql.update
         (fun wb version content ->
            Ocsigen_messages.console2 (Printf.sprintf "%d: wb %s, ver %ld%!"
                                (incr r; !r) (string_of_wikibox wb) version);
            match content with
              | None -> Lwt.return None
              | Some content ->
                  wp (sp, wb) content >>= fun r -> Lwt.return (Some r)
         )
       >>= fun () ->
       Ocsimore_page.html_page {{ [<p>"Done"] }}
    )

let () =
  Wiki_syntax.add_preparser_extension
    ~wp:Wiki_syntax.wikicreole_parser ~name:"wikibox"
  (fun (_sp, wb) args c ->
     Ocsigen_messages.console2 "Wikibox found";
     (try
        try
          Ocsigen_messages.console2 "Changing";
          let box = Int32.of_string (List.assoc "box" args) in
          Wiki_sql.wikibox_wiki wb >>= fun wid ->
          let wid = Wiki_ext.extract_wiki_id args wid in
          Ocsigen_messages.console2
            (Printf.sprintf "Changing %ld %s" box (string_of_wiki wid));
          Wiki_sql.wikibox_new_id wid box >>= fun box' ->
          Ocsigen_messages.console2
            (Printf.sprintf "New wikibox %s" (string_of_wikibox box'));
          let s = (Wiki_syntax.string_of_extension "wikibox"
                     (("box", string_of_wikibox box') ::
                        (* We remove the wiki information *)
                        List.remove_assoc "wiki" (List.remove_assoc "box" args)) c) in
          Lwt.return (Some s)

        with Not_found ->
          Ocsigen_messages.console2 "Error?";
          (* No box, the preparser extension will take care of this
             case, we do nothing *)
          Lwt.return None
      with Failure _ -> Ocsigen_messages.console2 "Error"; Lwt.return None
        | Not_found -> Ocsigen_messages.console2 "Box not found";
            Lwt.return None)
  )



(* Default permissions for the migration to the new permissions system *)
let _ = Lwt_unix.run
  (Wiki_sql.iter_wikis
     (fun { wiki_id = wiki; wiki_title = name} ->
        User.add_to_group ~user:(basic_user User.anonymous)
          ~group:(Wiki.wiki_wikiboxes_grps.grp_reader $ wiki)
        >>= fun () ->
        User.add_to_group ~user:(basic_user User.anonymous)
          ~group:(Wiki.wiki_files_readers $ wiki)
        >>= fun () ->
        try Scanf.sscanf name "wikiperso for %s"
          (fun user ->
             User.get_user_by_name user
             >>= fun user ->
             User.add_to_group ~user ~group:(Wiki.wiki_admins $ wiki)
          )
        with Scanf.Scan_failure _ -> Lwt.return ()

     ))
*)
