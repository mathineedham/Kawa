
(* The type of tokens. *)

type token = 
  | WHILE
  | VOID
  | VAR
  | THIS
  | SUPER
  | SUPEQ
  | SUP
  | SET
  | SEMI
  | RPAR
  | RETURN
  | PRINT
  | PLUS
  | OU
  | NOT
  | NEW
  | NEQU
  | MOINS
  | MOD
  | METHOD
  | MAIN
  | LPAR
  | INTCONST of (int)
  | INT
  | INSTANCEOF
  | INFEQ
  | INF
  | IF
  | IDENT of (string)
  | FOIS
  | FINAL
  | EXTENDS
  | ET
  | EQU
  | EOF
  | END
  | ELSE
  | DOT
  | DIVI
  | COMA
  | CLASS
  | BOOLCONST of (bool)
  | BOOL
  | BEGIN
  | ATTRIBUTE

(* This exception is raised by the monolithic API functions. *)

exception Error

(* The monolithic API. *)

val program: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (Kawa.program)
