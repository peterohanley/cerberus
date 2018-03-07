(* Created by Victor Gomes 2017-03-10 *)

open Util
open Core
open Cps_core
open Core_opt
open Pp_prelude
open Pp_ocaml

let print_head filename =
  !^"(* Generated by Cerberus from" ^^^ !^filename ^^ !^" *)" ^//^
  !^"open CoreStd"

let print_globals globs =
  let print_global_pair g =
    P.parens (!^"glob_" ^^ print_symbol g ^^ P.comma ^^^ print_symbol g)
  in
  List.map print_global_pair globs
  |> print_list id

let print_tags tags =
  let print_id_pair (cid, cty) =
    P.parens (print_cabs_id cid ^^ P.comma ^^^ print_ctype cty)
  in
  let print_tag_pairs (s, xs) =
    P.parens (print_raw_symbol s ^^ P.comma
              ^^^ print_list id (List.map print_id_pair xs))
  in
  let print_tag (s, tag) =
    match tag with
    | Tags.StructDef xs -> print_tag_pairs (s, xs)
    | Tags.UnionDef xs -> print_tag_pairs (s, xs)
  in
  print_list id (List.map print_tag (Pmap.bindings_list tags))

let print_foot tags globs main =
  match main with
  | Some main ->
    print_let !^"tags" (print_tags tags) ^//^
    print_let !^"globals" (print_globals globs.statics) ^//^
    print_let tunit (!^"A.run tags (List.rev_append"
                     ^^^ !^(globs.interface)
                     ^^ !^"ext_globals globals)"
                     ^^^ print_global_symbol main)
(* TODO: generate globals for empty main *)
  | None -> P.empty

let opt_passes core =
  elim_wseq core
  |> assoc_seq
  |> elim_skip
(*  |> elim_loc *) (* TODO: K to V, you shouldn't need this anymore since I removed Eloc *)
  |> elim_let

let create_globs name core =
  {
    interface = String.capitalize_ascii name ^ "I.";
    statics = List.map (fun (s,_,_) -> s) core.Core.globs;
    externs = Pmap.fold
        (fun s f es -> match f with
           | ProcDecl _ -> s::es
           | _ -> es
        ) core.funs [];
  }

let gen filename corestd sym_supply core =
  let fl = Filename.chop_extension filename in
  let globs = create_globs fl core in
  let cps_core = elim_proc_decls core
    |> run opt_passes
    |> cps_transform sym_supply globs.statics
  in
  let print_globals_init acc (sym, coreTy, bbs, bbody) =
    (if acc = P.empty then tletrec else acc ^//^ tand) ^^^
    print_eff_function (!^"glob_" ^^ print_symbol sym ^^^ print_symbol default) []
      (print_base_type coreTy) (print_transformed globs bbs bbody)
    ^/^ tand ^^^ print_symbol sym ^^^ P.equals ^^^ print_ref !^"A.null_ptr"
  in
  if corestd then
    Codegen_corestd.gen globs cps_core.impl cps_core.stdlib;
  Codegen_dep.gen fl globs.externs cps_core.funs globs.statics;
  let contents =
    print_head filename ^//^
    List.fold_left print_globals_init P.empty cps_core.globs ^//^
    print_funs globs cps_core.funs ^//^
    print_foot core.tagDefs globs core.main
  in
  let fl_ml = fl ^ ".ml" in
  let oc = open_out fl_ml in
  P.ToChannel.pretty 1. 80 oc contents;
  close_out oc;
  Exception.except_return 0
