open Util
open Util.Error

(** Types *)
type ty = TyArrow (* A function type, T -> T *) of ty * ty | TyBool

(** A lambda term, using de Bruijn indeces. *)
type term =
  (* A variable "x" *)
  | TmVar of info * int * int (* length of context checked for validation *)
  (* A function definition "λx: T. <definition>" *)
  | TmAbs of info * string (* name hint *) * ty * term
  (* A function application "(λx: T. <definition>)(y)" *)
  | TmApp of info * term * term
  (* A "true" clause *)
  | TmTrue of info
  (* A "true" clause *)
  | TmFalse of info
  (* A condition/then/else expression *)
  | TmIf of info * term * term * term

(** Get term info *)
let tmInfo t =
  match t with
  | TmVar (info, _, _) -> info
  | TmAbs (info, _, _, _) -> info
  | TmApp (info, _, _) -> info
  | TmTrue info -> info
  | TmFalse info -> info
  | TmIf (info, _, _, _) -> info

type binding =
  | NameBinding
  | (* A typed variable declaration. *) VarBinding of ty

(*** Commands ***)
type command = Eval of info * term | Bind of info * string * binding

(*** Context ***)
type context = (string * binding) list

let emptycontext = []

let ctxlength ctx = List.length ctx

let addbinding ctx x bind = (x, bind) :: ctx

let addname ctx name = addbinding ctx name NameBinding

let rec isNameBound ctx name =
  match ctx with
  | [] -> false
  | (cand, _) :: rest -> if cand = name then true else isNameBound rest name

(** Picks the first variable name derived from [name] that is not already bound
    in [context ctx]. *)
let rec freshname ctx name =
  if isNameBound ctx name then freshname ctx (name ^ "'")
  else ((name, NameBinding) :: ctx, name)

let index2name info ctx x =
  try
    let xn, _ = List.nth ctx x in
    xn
  with Failure _ ->
    let msg =
      Printf.sprintf "Variable lookup failure: offset %d, ctx size: %d"
    in
    error info (msg x (List.length ctx))

let rec name2index info ctx x =
  match ctx with
  | [] -> error info ("Identifier " ^ x ^ " is unbound")
  | (cand, _) :: rest -> if cand = x then 0 else 1 + name2index info rest x

let getbinding info ctx i =
  try
    let _, binding = List.nth ctx i in
    binding
  with Failure _ ->
    let msg =
      Printf.sprintf "Variable lookup failure: offset: %d, ctx size: %d"
    in
    error info (msg i (List.length ctx))

let gettype info ctx i =
  match getbinding info ctx i with
  | VarBinding tyT -> tyT
  | _ ->
      error info
        ( "gettype: Variable " ^ index2name info ctx i
        ^ " does not have a type binding." )

(*** Shifting ***)

(** [termShift] renumbers indices of free variables in a term when a
    substitution occurs to avoid conflation with bound variables.

    For example, consider
      shift 2 (λ. 0 1 (λ. 0 1 2))
    The initial cutoff is 0 (meaning that we are willing to rename all
    variables). As we enter an abstraction, we increase the cutoff (because
    the application introduces the de Bruijn index cuttof+1). In the example,
      shift 2 (λ. 0 1 (λ. 0 1 2))
               ^^ binds 0
                       ^^ binds 1
    Okay, so let's walk out the shifting process. Entering the first
    abstraction, we get
      (λ. 0 3 [shift c=1 2] (λ. 0 1 2))
    And now, walking out the rest of the shift in the second abstraction, we
    arrive at
      (λ. 0 3 (λ. 0 1 4))
    As you can see, we preserved the structure of the bound variables while
    permissively renaming the free variables, which we are up to doing so
    since they have no binding. Expressed as variables, maybe this would be a
    shift from
      (λa. a b (λb. a b c))
    to
      (λa. a d (λb. a b e)) *)
let termShift d term =
  (* walk c=cutoff *)
  let rec walk c term =
    match term with
    | TmVar (info, x, n) ->
        if x < c then
          (* Under cutoff <=> bound variable, no shift. *)
          TmVar (info, x, n + d)
        else (* Otherwise, apply the shift. *)
          TmVar (info, x + d, n + d)
    | TmAbs (info, name, ty, term) -> TmAbs (info, name, ty, walk (c + 1) term)
    | TmApp (info, t1, t2) -> TmApp (info, walk c t1, walk c t2)
    | TmTrue _ as t -> t
    | TmFalse _ as t -> t
    | TmIf (info, cond, thn, els) ->
        TmIf (info, walk c cond, walk c thn, walk c els)
  in
  walk 0 term

(** Applies the substitution [j->s]term *)
let termSubst j s term =
  let rec walk c term =
    match term with
    | TmVar (info, x, n) ->
        if x = j + c then
          (* Term indices match, apply substitution *)
          termShift c s
        else (* Do not apply substitution *) TmVar (info, x, n)
    | TmAbs (info, name, ty, term) ->
        (* Entered an abstraction, so we need to shift up the term before substitution *)
        TmAbs (info, name, ty, walk (c + 1) term)
    | TmApp (info, t1, t2) -> TmApp (info, walk c t1, walk c t2)
    | TmTrue _ as t -> t
    | TmFalse _ as t -> t
    | TmIf (info, cond, thn, els) ->
        TmIf (info, walk c cond, walk c thn, walk c els)
  in
  walk 0 term

(** Substitutes a term on a "top level" bound variable. Shift up replacement
    term by 1, perform the substitution with the bound variable, and then
    shift everything down by 1 to account for the used up bound variable. *)
let termSubstTop s term = termShift (-1) (termSubst 0 (termShift 1 s) term)

(*** Printing ***)
let rec printty ty =
  match ty with
  | TyArrow (f, t) ->
      printty f;
      pr " -> ";
      printty t
  | TyBool -> pr "bool"

let rec printtm ctx t =
  match t with
  | TmVar (info, x, n) ->
      if ctxlength ctx = n then pr (index2name info ctx x)
      else
        pr
          ( "[bad index: " ^ string_of_int x ^ "/" ^ string_of_int n ^ " in {"
          ^ List.fold_left (fun s (x, _) -> s ^ " " ^ x) "" ctx
          ^ " }]" )
  | TmAbs (_, name, ty, term) ->
      let ctx', name' = freshname ctx name in
      pr "(λ ";
      pr name';
      pr ": ";
      printty ty;
      pr ". ";
      printtm ctx' term;
      pr ")"
  | TmApp (_, t1, t2) ->
      pr "(";
      printtm ctx t1;
      pr " <- ";
      printtm ctx t2;
      pr ")"
  | TmTrue _ -> pr "true"
  | TmFalse _ -> pr "false"
  | TmIf (_, cond, thn, els) ->
      pr "if ";
      printtm ctx cond;
      pr " then ";
      printtm ctx thn;
      pr " else ";
      printtm ctx els

let printbinding _ctx b =
  match b with
  | NameBinding -> ()
  | VarBinding ty ->
      pr ": ";
      printty ty
