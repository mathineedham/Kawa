%{

  open Lexing
  open Kawa

%}

(* Liste de lexèmes *)
%token <int> INTCONST
%token <bool> BOOLCONST
%token PLUS MOINS FOIS DIVI MOD NOT 
%token INF SUP SUPEQ INFEQ EQU NEQU OU ET
%token <string> IDENT
%token MAIN RETURN  VOID BOOL INT 
%token VAR ATTRIBUTE METHOD NEW THIS CLASS DOT EXTENDS
%token LPAR RPAR BEGIN END SEMI IF ELSE  WHILE
%token PRINT SET COMA 
%token SUPER INSTANCEOF FINAL
%token EOF

(* Priorités du moins prioritaire au plus*)
%left ET OU(* a && b && c  vaut ( a && b ) && c et a || b || c  vaut ( a || b ) || c *)
(*erreur de a op b op c: normal parce qu'on veut une comparaison entre 2 objet*)
%nonassoc INF SUP SUPEQ INFEQ EQU NEQU 
%left MOINS PLUS (* a + b + c vaut ( a + b ) + c *)
%left FOIS DIVI MOD(* a * b * c vaut ( a * b ) * c*)
%left INSTANCEOF (* a + b instanceof typ = a + (b instanceof typ*) 
%left DOT (* a+ b.c = a + (b.c) ET a.b.c=(a.b).c) ET a.c instance of typ = (a.c) instance of *)
(* priorite reduction unaire:
 - x + y vaut (- x) + y et
 et ! a || b vaut (! a) || b *)
%nonassoc UNAIRE 


%start program
%type <Kawa.program> program

%%

program:
| globals_and_sets = declarations_lines
  classes=list(class_definition)
  MAIN BEGIN main_code=instructions END EOF
  { let l = List.split globals_and_sets in 
    {classes; 
    globals=(fst l); 
    main=(List.append (List.find_all (fun e ->  e <>Return(Bool(false))) (snd l)) main_code)} } 
;

expression:
| LPAR e=expression RPAR { e }
| n=INTCONST   { Int(n) }
| b=BOOLCONST  { Bool(b) }
| o=unop e=expression %prec UNAIRE 
  { Unop(o,e) }
| e1=expression o=binop e2=expression 
  { Binop(o,e1,e2) }
| s=memory_acess { Get(s) }
| THIS { This }
| NEW s=IDENT { New(s) }
| NEW s=IDENT LPAR params=separated_list(COMA,expression) RPAR { NewCstr(s,params)}
| e=expression DOT s=IDENT LPAR params=separated_list(COMA,expression) RPAR { MethCall(e,s,params) }
| e=expression INSTANCEOF t=typ { InstanceOf(e,t) }
| SUPER { Super }
;

instructions:
|l=list(instruction) { List.flatten l}
;

instruction:
| PRINT LPAR e=expression RPAR SEMI { [Print(e)] }
| IF LPAR e=expression RPAR BEGIN l1=instructions
  END ELSE BEGIN l2=instructions END { [If(e,l1,l2)] }
| IF LPAR e=expression RPAR BEGIN l1=instructions END { [If(e,l1,[])] }
| WHILE LPAR e=expression RPAR BEGIN l=instructions END { [While(e,l)] }
| RETURN e=expression SEMI { [Return(e)] }
| e=expression SEMI { [Expr(e)] } 
| m=memory_acess SET e=expression SEMI { [Set(m,e)] }
| d=delimited(VAR,vars,SEMI){List.flatten (List.map (fun (x,e) ->(
            match e with
            |None ->  [NewVar(fst x, snd x)]
            |Some e1 -> [NewVar(fst x, snd x); Set(Var(fst x),e1)])
            ) d)}
;

memory_acess:
| s=IDENT { Var(s) }
| e=expression DOT s=IDENT{ Field(e,s) }
;


declarations_lines:
| decls = list(delimited(VAR,vars,SEMI)) 
{(List.map (fun (x,e) ->(
            match e with
            |None ->  (x, Return(Bool(false)))
            |Some e1 -> (x,Set(Var(fst x),e1)))
            )  (List.flatten(decls)))}
; 

vars:
| t=typ ids=separated_nonempty_list(COMA, IDENT)  
   {List.map (fun id -> ((id, t),None)) ids}
| t=typ id=IDENT SET e=expression 
  {[(id,t), Some e]}
;

attributes_lines :
| atts = list(delimited(ATTRIBUTE,attributes,SEMI)) { (List.flatten(atts))}
; 

attributes:
| final=option(FINAL) t=typ ids=separated_nonempty_list(COMA, IDENT)  
   {match final with
   |None ->List.map (fun id -> (((id, t),false))) ids
   |Some _ ->List.map (fun id -> (((id, t),true))) ids}
;

parametres :
| t=typ s=IDENT { (s,t) }
; 

class_definition :
| CLASS class_name=IDENT parent=option(preceded(EXTENDS,IDENT))
   BEGIN attributes=attributes_lines
   methods=list(methods_definition) END
  { {class_name; attributes; methods; parent} }
;


methods_definition :
| METHOD return=typ method_name=IDENT LPAR 
  params=separated_list(COMA,parametres) RPAR
  BEGIN code=instructions END 
  { {method_name; code; params; locals=[]; return} }
;

%inline typ:
| INT     { TInt }
| BOOL    { TBool }
| c=IDENT { TClass(c) }
| VOID    { TVoid }
; 

%inline binop:
| PLUS  { Add }
| FOIS  { Mul }
| MOINS { Sub }
| DIVI  { Div }
| SUP   { Gt }
| INF   { Lt }
| INFEQ { Le }
| SUPEQ { Ge }
| EQU   { Eq }
| NEQU  { Neq }
| OU    { Or }
| ET    { And }
| MOD   { Rem }
;

%inline unop:
| NOT   { Not }
| MOINS { Opp }
;



