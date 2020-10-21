open Resultat
open TypeErrors
open Environment
module SymSet = Set.Make(Sym)

(* module E = Environment
 * module L = Local
 * module Loc = Locations
 * module BT = BaseTypes
 * module LS = LogicalSorts
 * module RE = Resources
 * module RT = ReturnTypes
 * module AT = ArgumentTypes
 * open BT
 * open LS
 * open TypeErrors
 * open Local
 * open Environment
 * open ReturnTypes *)



module WIT = struct

  open BaseTypes
  open LogicalSorts
  open IndexTerms

  type t = IndexTerms.t

  let rec infer (loc: Loc.t) {local;global} (it: t) : LogicalSorts.t m = 
    match it with
    | Num _ -> return (Base Integer)
    | Bool _ -> return (Base Bool)
    | Add (t,t') | Sub (t,t') | Mul (t,t') | Div (t,t') 
    | Exp (t,t') | Rem_t (t,t') | Rem_f (t,t') 
    | Min (t,t') | Max (t,t') ->
       let* () = check_aux loc it {local;global} (Base Integer) t in
       let* () = check_aux loc it {local;global} (Base Integer) t' in
       return (Base Integer)
    | LT (t,t') | GT (t,t') | LE (t,t') | GE (t,t') ->
       let* () = check_aux loc it {local;global} (Base Integer) t in
       let* () = check_aux loc it {local;global} (Base Integer) t' in
       return (Base Bool)
    | EQ (t,t') | NE (t,t') ->
       let* ls = infer loc {local;global} t in
       let* () = check_aux loc it {local;global} ls t' in
       return (Base Bool)
    | Null t ->
       let* () = check_aux loc it {local;global} (Base Loc) t in
       return (Base Bool)
    | And ts | Or ts ->
       let* () = ListM.iterM (check_aux loc it {local;global} (Base Bool)) ts in
       return (Base Bool)
    | Impl (t,t') ->
       let* () = check_aux loc it {local;global} (Base Bool) t in
       let* () = check_aux loc it {local;global} (Base Bool) t' in
       return (Base Bool)
    | Not t ->
       let* () = check_aux loc it {local;global} (Base Bool) t in
       return (Base Bool)
    | ITE (t,t',t'') ->
       let* () = check_aux loc it {local;global} (Base Bool) t in
       let* ls = infer loc {local;global} t' in
       let* () = check_aux loc it {local;global} ls t'' in
       return ls
    | Tuple its ->
       let* ts = 
         ListM.mapM (fun it -> 
             let* (Base bt) = infer loc {local;global} it in
             return bt
           ) its in
       return (Base (BT.Tuple ts))
    | Nth (bt, n, it') ->
       let* t = check_aux loc it {local;global} (Base bt) it' in
       begin match bt with
       | Tuple ts ->
          begin match List.nth_opt ts n with
          | Some t -> return (Base t)
          | None -> fail loc (Illtyped_it it)
          end
       | _ -> fail loc (Illtyped_it it)
       end
    | Struct (tag, members) ->
       let* decl = Global.get_struct_decl loc global.struct_decls tag in
       let* () = 
         ListM.iterM (fun (member,it') ->
             let* mbt = Tools.assoc_err loc member decl.raw (Illtyped_it it) in
             check_aux loc it {local;global} (Base mbt) it'
           ) members
       in
       return (Base (Struct tag))
    | Member (tag, it', member) ->
       let* () = check_aux loc it {local;global} (Base (Struct tag)) it' in
       let* decl = Global.get_struct_decl loc global.struct_decls tag in
       let* bt = Tools.assoc_err loc member decl.raw (Illtyped_it it) in
       return (Base bt)
    | MemberOffset (tag, it', member) ->
       let* () = check_aux loc it {local;global} (Base Loc) it' in
       let* decl = Global.get_struct_decl loc global.struct_decls tag in
       let* _ = Tools.assoc_err loc member decl.raw (Illtyped_it it) in
       return (Base Loc)
    | Nil bt -> 
       return (Base bt)
    | Cons (it1,it2) ->
       let* (Base item_bt) = infer loc {local;global} it1 in
       let* () = check_aux loc it {local;global} (Base (List item_bt)) it2 in
       return (Base (List item_bt))
    | List (its,bt) ->
       let* () = ListM.iterM (check_aux loc it {local;global} (Base bt)) its in
       return (Base bt)
    | Head it' ->
       let* ls = infer loc {local;global} it' in
       begin match ls with
       | Base (List bt) -> return (Base bt)
       | _ -> fail loc (Illtyped_it it)
       end
    | Tail it' ->
       let* ls = infer loc {local;global} it in
       begin match ls with
       | Base (List bt) -> return (Base (List bt))
       | _ -> fail loc (Illtyped_it it)
       end
    | S s ->
       Local.get_l loc s local

  and check_aux loc (context: t) env (ls: LS.t) (it: t) : unit m = 
    let* ls' = infer loc env it in
    if LS.equal ls ls' then return ()
    else fail loc (Illtyped_it context)

  let check loc env ls it = check_aux loc it env ls it

  let welltyped loc env it = 
    let* _ = infer loc env it in
    return ()

end


module WRE = struct
  open Resources
  type t = Resources.t
  let welltyped loc env = function
    | Uninit u -> WIT.check loc env (LS.Base BT.Loc) u.pointer
    | Points p -> WIT.check loc env (LS.Base BT.Loc) p.pointer
end


module WLC = struct
  open LogicalConstraints
  type t = LogicalConstraints.t
  let welltyped loc env = function
    | LC it -> WIT.check loc env (LS.Base BT.Bool) it
end


module WRT = struct

  open ReturnTypes
  type t = ReturnTypes.t

  let rec welltyped_l loc {local; global} lrt = 
    match lrt with
    | Logical ((s,ls), lrt) -> 
       let local = Local.add_l s ls local in
       welltyped_l loc {local; global} lrt
    | Resource (re, lrt) -> 
       let* () = WRE.welltyped loc {local; global} re in
       welltyped_l loc {local; global} lrt
    | Constraint (lc, lrt) ->
       let* () = WLC.welltyped loc {local; global} lc in
       welltyped_l loc {local; global} lrt
    | I -> 
       return ()

  let welltyped loc {local; global} rt = 
    match rt with 
    | Computational ((name,bt), lrt) ->
       let lname = Sym.fresh_relative name (fun s -> s ^ "_l") in
       let local = Local.add_l lname (LS.Base bt) local in
       let local = Local.add_a name (bt, lname) local in
       let lrt = subst_var_l Subst.{before = name; after = lname} lrt in
       welltyped_l loc {local; global} lrt

end

module WFalse = struct
  type t = False.t
  let welltyped _ _ _ = return ()
end


module type WI_Sig = sig
  type t
  val welltyped : Loc.t -> pexpr_environment -> t -> unit m
end


module WAT (I: ArgumentTypes.I_Sig) (WI: WI_Sig with type t = I.t) = struct

  module T = ArgumentTypes.Make(I)

  type t = T.t

  let rec check loc {local; global} (at : T.t) : unit m = 
    let open Resultat in
    match at with
    | T.Computational ((name,bt), at) ->
       let lname = Sym.fresh_relative name (fun s -> s ^ "_l") in
       let local = Local.add_l lname (LS.Base bt) local in
       let local = Local.add_a name (bt, lname) local in
       let at = T.subst_var Subst.{before = name; after = lname} at in
       check loc {local; global} at
    | T.Logical ((s,ls), at) -> 
       let local = Local.add_l s ls local in
       check loc {local; global} at
    | T.Resource (re, at) -> 
       let* () = WRE.welltyped loc {local; global} re in
       check loc {local; global} at
    | T.Constraint (lc, at) ->
       let* () = WLC.welltyped loc {local; global} lc in
       check loc {local; global} at
    | T.I i -> 
       WI.welltyped loc {local; global} i


  let wellpolarised loc determined ft = 
    let open Resultat in
    let rec aux determined undetermined ft = 
    match ft with
    | T.Computational ((s, _), ft) ->
       aux (SymSet.add s determined) undetermined ft
    | T.Logical ((s, _), ft) ->
       aux determined (SymSet.add s undetermined) ft
    | T.Resource (re, ft) ->
       begin match SymSet.elements (SymSet.diff (RE.input re) determined) with
       | [] ->
          let fixed = RE.output re in
          let determined = SymSet.union determined fixed in
          let undetermined = SymSet.diff undetermined fixed in
          aux determined undetermined ft
       | s :: _ -> 
          fail loc (Unconstrained_logical_variable s)
       end
    | T.Constraint (_, ft) ->
       aux determined undetermined ft
    | T.I _ ->
       match SymSet.elements undetermined with
       | [] -> return ()
       | s :: _ ->  fail loc (Unconstrained_logical_variable s)
    in
    aux determined SymSet.empty ft

  let welltyped loc {local; global} at = 
    let* () = check loc {local; global} at in
    wellpolarised loc (SymSet.of_list (Local.all_names local)) at

end


module WFT = WAT(ReturnTypes)(WRT)
module WLT = WAT(False)(WFalse)
