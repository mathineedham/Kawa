open Kawa

exception Error of string
let error s = raise (Error s)
let type_error ty_actual ty_expected =
  error (Printf.sprintf "expected %s, got %s"
           (typ_to_string ty_expected) (typ_to_string ty_actual))

module Env = Map.Make(String)
type tenv = typ Env.t


let add_env l ttenv =
  List.fold_left (fun env (x, t) -> Env.add x t env) ttenv l

let typecheck_prog p =
  let tenv = add_env p.globals Env.empty in
  let local_env = Hashtbl.create 16 in
  
  (*function that creates a list of all attributes a class depending on its parent classes*)
  let rec attributes clsname l =
    let cls = (List.find (fun x -> x.class_name = clsname) p.classes) in
    match List.find_opt (fun a-> (List.exists (fun a2 -> (fst (fst a2))=(fst (fst a))) l) ) cls.attributes with
    (*none of the attributes from our current class and any of its subclass share a name*)
    |None ->
      begin
        match cls.parent with
        |Some par ->
          begin
            match List.find_opt (fun x -> x.class_name = par) p.classes with
            |None -> assert false
            |Some c -> attributes par (List.append cls.attributes l)
          end
        |None -> List.append cls.attributes l
      end
    |Some att -> raise (Error(Printf.sprintf "a subclass of the class %s cannot have an attribute called %s as it inherits one already" clsname (fst(fst att)) ))
  in
  let class_attributes = List.map (fun c ->  (c.class_name,attributes c.class_name [])) p.classes in
  
  (*function that correctly gives you all the attributes of a class*)
  let attributes cls =
    match List.find_opt (fun pair -> fst pair = cls.class_name) class_attributes with
    |None -> assert false 
    |Some v ->  snd v
  in
  
  let rec parent_list clsname l =
    let cls = (List.find_opt (fun x -> x.class_name = clsname) p.classes )in
    match cls with
    |None -> assert false
    |Some cls1 -> begin
      match cls1.parent with
      | None -> l 
      | Some par -> parent_list par (par::l)
    end
  in

  (*methods_list->string->string opt->method_def list*)
  (*function that recursively finds all the methods of a class*)
  let rec methods_list clsname l =
    let cls = (List.find (fun x -> x.class_name = clsname) p.classes )in
    (*we only add to our list of methods a method from a parent class
        if it has not been overwritten in one of its children*)
    let cls_meth =  List.find_all (fun m -> not(List.exists (fun m2 -> m2.method_name=m.method_name) l))
                  (cls.methods) in
    (*recursion until no parent*)
    match cls.parent with
    |None -> List.append cls_meth l
    |Some par -> 
      begin
        match List.find_opt (fun x -> x.class_name = par) p.classes with
        |None -> assert false
        |Some c -> methods_list par (List.append cls_meth l)
      end
  in

  (*check->expression->typ->tenv->hashtbl string*typ ->unit*)
  let rec check e typ tenv lenv =
    let typ_e = type_expr e tenv  lenv in
    if typ_e <> typ then type_error typ_e typ

  (*check_set->expression->typ->tenv->hashtbl string*typ ->unit*)
  and check_set e typ tenv lenv =
    let typ_e = type_expr e tenv  lenv in
    match typ_e, typ with
    |TClass(c), TClass(c2) -> 
      let parent_classes = parent_list c [] in  
      if not(List.mem c2 parent_classes)&&(c<>c2) then raise (Error (Printf.sprintf "expected %s or sub classes, got %s" c2 c))
    |_ , _ -> if typ_e <> typ then type_error typ_e typ

  (*type_expr->expression->tenv->typ*)
  and type_expr e tenv lenv = match e with
    | Int _  -> TInt
    | Bool _ -> TBool
    | Unop(op,expr) -> 
      begin
        match op with
        |Opp  -> begin check expr TInt tenv lenv; TInt end
        |Not -> begin check expr TBool tenv lenv; TBool end
      end
    | Binop(op,expr1,expr2) -> 
      begin
        match op with  
        |Eq|Neq -> 
          begin
            (*on trouve le type de expr1, 
              on verifie que expr2 est du meme type
            et si oui, on sait que on aura un bool*)
            let type_e1 = type_expr expr1 tenv lenv in 
            check expr2 type_e1 tenv lenv;
            TBool
          end
        |And|Or -> 
          begin
            check expr1 TBool tenv lenv;
            check expr2 TBool tenv lenv;
            TBool
          end
        |Add|Sub|Mul|Div|Rem ->
          begin
            check expr1 TInt tenv lenv;
            check expr2 TInt tenv lenv;
            TInt
          end   
        |Lt|Le|Gt|Ge -> 
          begin
            check expr1 TInt tenv lenv;
            check expr2 TInt tenv lenv;
            TBool
          end   
      end
    | Get(m) -> type_mem_access m tenv lenv
    | New(s) -> 
      begin
        match (List.find_opt (fun c -> c.class_name = s) p.classes) with
        |None -> raise (Error (Printf.sprintf "the class %s does not exist" s))
        |Some _ -> TClass s
      end
    | MethCall(e,methname,param) -> 
      let o = type_expr e tenv lenv in
        begin
          match o with
          |TBool | TInt | TVoid -> raise (Error (Printf.sprintf "the variable is not an object " ))
          |TClass c -> 
            let cls_methods = methods_list c [] in
            begin
              match List.find_opt (fun m -> m.method_name= methname)  cls_methods with
              |None -> raise (Error (Printf.sprintf "the class %s has no methode by the name of %s" c methname) )
              |Some meth_def -> 
                begin
                  if (List.length param)<>(List.length meth_def.params) then raise (Error (Printf.sprintf "number of arguments given to the call of method %s were wrong"  methname))
                  else
                  for i= 0 to (List.length meth_def.params -1) do
                    check (List.nth param i ) (snd (List.nth meth_def.params i)) tenv lenv 
                  done;
                  meth_def.return
                end 
            end
      end
    | This -> 
      begin
        match (Hashtbl.find_opt lenv "this") with
        |Some t ->  t
        |None-> raise (Error (Printf.sprintf "no current object can be attained through token this" )) 
      end
    | Super -> 
      begin
        match (Hashtbl.find_opt lenv "this") with
        |Some t -> 
          begin
            match t with
            |TClass c ->
              begin
                match (List.find (fun s -> s.class_name = c) p.classes).parent with
                |Some par -> TClass (List.find (fun s -> s.class_name = par) p.classes).class_name
                |None -> raise (Error (Printf.sprintf "the class %s has no parent to which super could refer" c)) 
              end
            |_ -> raise (Error (Printf.sprintf "you are outside of reach of a super" )) 
          end
        |None-> raise (Error (Printf.sprintf "you are outside of reach of a super" )) 
      end
    | NewCstr (s, param) -> 
      begin
        match (List.find_opt (fun c -> c.class_name = s) p.classes) with
        |None -> raise (Error (Printf.sprintf "the class %s does not exist" s))
        |Some c ->
          let cls_methods = methods_list c.class_name [] in
            begin
              match List.find_opt (fun m -> m.method_name= "constructor")  cls_methods with
              |None -> raise (Error (Printf.sprintf "the class %s has no constructor" c.class_name) )
              |Some meth_def -> 
                begin
                  if (List.length param)<>(List.length meth_def.params) 
                    then raise (Error (Printf.sprintf "number of arguments given to the constructor was wrong"))
                  else if (meth_def.return<>TVoid) 
                    then raise (Error (Printf.sprintf "constructor must be of type void"))
                  else
                  for i= 0 to (List.length meth_def.params -1) do
                    check (List.nth param i ) (snd (List.nth meth_def.params i)) tenv lenv 
                  done;
                  TClass s
                end 
          end
      end
    | InstanceOf (e, typ) -> TBool
  
  (*type_mem_access->mem_access->tenv->unit*)
  and type_mem_access m tenv lenv= match m with
    | Var(s) -> begin 
        match (Env.find_opt s tenv), (Hashtbl.find_opt lenv s ) with
          |Some(t),None -> t 
          |_,Some(t) -> t
          |None,None -> raise (Error (Printf.sprintf "variable %s was not declared" s))
      end
    | Field (e,s) -> 
      match e with 
      |Super -> raise (Error (Printf.sprintf "you cannot access memory via super" ))
      |_ ->
      let o = type_expr e tenv lenv in 
      match o with
      |TBool | TInt | TVoid -> raise (Error (Printf.sprintf "the variable %s is not an object " s))
      |TClass c ->
        begin
        let clsdef = List.find (fun a -> a.class_name =c) p.classes in
        match List.find_opt (fun att -> fst (fst att) = s) (attributes clsdef) with
        |None -> raise (Error (Printf.sprintf "this object does not have a field named %s" s))
        |Some att -> snd (fst att)
        end

  in

  (*check_instr->instr->typ->tenv->unit*)
  let rec check_instr i ret tenv lenv = match i with
    | Print e -> check e TInt tenv lenv
    | Expr e -> check e TVoid tenv lenv
    | Return e -> check e ret tenv lenv
    | If(e,s1,s2) -> check e TBool tenv lenv 
    | While(e,s)-> check e TBool tenv lenv 
    | Set(m,e)-> check_set e (type_mem_access m tenv lenv) tenv lenv
    | NewVar (s, t) -> Hashtbl.add lenv s t  
  (*check_seq->list instr->typ->tenv->unit*)
  and check_seq s ret tenv lenv =
    List.iter (fun i -> check_instr i ret tenv lenv) s
  in

  (*checks that all methods from classes are correctly declared in their type*)
  for i = 0 to (List.length p.classes -1) do
    let c = List.nth p.classes i in
    for j = 0 to (List.length c.methods -1) do 
      let m = List.nth c.methods j in
      let lenv = Hashtbl.create 16 in 
      (*add each of our arguments into the environment*)
      for h= 0 to (List.length m.params -1) do
        let arg = List.nth m.params h in
        Hashtbl.add lenv (fst arg) (snd arg) ; 
      done;
      (*add both our variable this and our result variable*)
      Hashtbl.add lenv "this" (TClass c.class_name) ;
      Hashtbl.add lenv "call_result" m.return; 
      check_seq m.code m.return tenv lenv
    done;
  done;

  (*check that the main programm is of typ void*)
  check_seq p.main TVoid tenv local_env 

  
  
