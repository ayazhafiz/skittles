open Language
open Language.Ast
open Typecheck

let string_of_ty = Language.string_of_ty

let string_of_term = Language.string_of_term dnf_plus

let rec flatten_ty_in_term t =
  match t with
  | Num _ | Var _ -> t
  | Tup (ts, ty) -> Tup (List.map flatten_ty_in_term ts, ty)
  | App (fn, t, ty) -> App (fn, List.map flatten_ty_in_term t, ty)
  | Dec (fn, params, body, cont, ty) ->
      List.iter
        (function
          | _, ty, _ when needs_inference !ty -> ()
          | _, ty, _ -> ty := flatten_ty !ty)
        params;
      Dec (fn, params, flatten_ty_in_term body, flatten_ty_in_term cont, ty)
  | If (var, isty, then', else', ty) ->
      If
        ( var,
          flatten_ty isty,
          flatten_ty_in_term then',
          flatten_ty_in_term else',
          ty )

let lex = Lexing.from_string ~with_positions:true

let parse_term s =
  lex s |> Parser.toplevel_term Lexer.read |> flatten_ty_in_term

let parse_ty s = lex s |> Parser.toplevel_ty Lexer.read |> flatten_ty

type dnf = Typecheck.dnf

let dnf = Typecheck.dnf

let ty_of_dnf = Typecheck.ty_of_dnf

let dnf_plus = Typecheck.dnf_plus

let ( <: ) = Typecheck.( <: )

let typecheck = Typecheck.typecheck

let infer_types = Infer.infer_types
