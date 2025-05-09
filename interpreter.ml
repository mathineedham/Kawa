open Kawa

type value =
  | VInt  of int
  | VBool of bool
  | VObj  of obj
  | Null
and obj = {
  cls:    string;
  fields: (string, value) Hashtbl.t;
}

exception Error of string
exception Return of value

let exec_prog (p: program): unit =

  (*becomes true only in a constructor pf a certain class,
   which allows the final attributes of that class to be changed*) 
  let is_constructor = ref (false,"") in 

  (*function that creates a list of all attributes a class depending on its parent classes*)
  let rec attributes clsname l =
    let cls = (List.find (fun x -> x.class_name = clsname) p.classes) in
    match List.find_opt (fun a-> (List.exists (fun a2 -> (fst a2)=(fst a)) l) ) cls.attributes with
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
    |Some att -> raise (Error(Printf.sprintf "a subclass of the class %s cannot have an attribute called %s as it inherits one already" clsname (fst (fst att)) ))
  in
  let class_attributes = List.map (fun c ->  (c.class_name,attributes c.class_name [])) p.classes in
  
  (*function that correctly gives you all the attributes of a class*)
  let attributes cls =
    match List.find_opt (fun pair -> fst pair = cls.class_name) class_attributes with
    |None -> assert false 
    |Some v -> snd v
  in
  
  (*string->VObj*)
  (*creates a new instance of a class named clsname*)
  let create_struct clsname  =
    match (List.find_opt (fun c -> c.class_name = clsname) p.classes) with
    |None -> raise (Error(Printf.sprintf "there is no class by the name of %s" clsname))
    |Some c -> begin
      let att = Hashtbl.create 16 in
      List.iter (fun (x,_) -> Hashtbl.add att (fst x) Null) (attributes c);
      {cls=clsname; fields=att}
    end
  in
  
  (*string->string->bool*)
  let is_final clsname fieldname =
    match List.find_opt (fun x -> x.class_name = clsname) p.classes with
    |None -> assert false
    |Some cls -> 
      begin
        match List.find_opt (fun f -> fst (fst f)=fieldname) (attributes cls) with
        |None -> assert false
        |Some v -> snd v
      end
  in

  (*we create our global variables' environment*)
  let env = Hashtbl.create 16 in
  List.iter (fun (x, t) -> match t with 
                          |TClass(c) -> Hashtbl.add env x (VObj (create_struct c))
                          |_ -> Hashtbl.add env x Null) p.globals;  

  (*string->string opt->method_def list*)
  (*function that recursively finds all the methods of a class*)
  (*clsname MUST be a valid class name*)
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

  (*method_def->VObj->value list->value*)
  (*None of the method's arguments can be called call_result!!*)
  let rec eval_call f this args  =
    let call_env = Hashtbl.create 16 in (*new environment for our method call*)
    
    (*add each of our arguments with their input value into the environment*)
    for i= 0 to (List.length args -1) do
      let arg_name = fst (List.nth f.params i) in
      Hashtbl.add call_env arg_name (List.nth args i ) ; 
    done;
    (*add both our variable this and our result variable*)
    Hashtbl.add call_env "this" this ;
    Hashtbl.add call_env "call_result" Null; 
    
    (*excecute method code*)
    exec_seq f.code call_env;

    (*returns the value of the result of the function*)
    Hashtbl.find call_env "call_result"; 
 
  (*exec_seq->list instr->env->unit*)
  and exec_seq s lenv =
    let rec evali e = match eval e with
      | VInt n -> n
      | _ -> assert false
    and evalb e = match eval e with
      | VBool b -> b
      | _ -> assert false
    and evalo e = match eval e with
      | VObj o -> o
      | _ -> assert false
    and eval (e: expr): value = match e with
      | Int n  -> VInt n
      | Bool b -> VBool b
      | Unop(op,expr) -> 
        begin
          match op with
          |Opp -> (VInt (- (evali expr)))
          |Not -> (VBool(not (evalb expr)))
        end
      | Binop(op,expr1,expr2) -> 
        begin
          match op with  
          |Eq -> VBool ((eval expr1) = (eval expr2))
          |Neq -> VBool ((eval expr1) <> (eval expr2))
          |And -> VBool ((evalb expr1) && (evalb expr2))
          |Or -> VBool ((evalb expr1) || (evalb expr2))
          |Add -> VInt ((evali expr1) + (evali expr2))
          |Sub -> VInt ((evali expr1) - (evali expr2))
          |Mul -> VInt ((evali expr1) * (evali expr2))
          |Div -> VInt ((evali expr1) / (evali expr2))
          |Rem -> VInt ((evali expr1) mod (evali expr2))
          |Lt -> VBool ((evali expr1) < (evali expr2))
          |Le -> VBool ((evali expr1) <= (evali expr2))
          |Gt -> VBool ((evali expr1) > (evali expr2))
          |Ge -> VBool ((evali expr1) >= (evali expr2))
        end
      | Get(m) -> eval_mem m 
      | New(s) -> VObj (create_struct s)
      | MethCall(e,methname,params) ->
        begin
          match e with 
          |Super ->  
            let obj = evalo e in
            let c = List.find(fun m -> m.class_name = obj.cls) p.classes in
            begin
              match c.parent with
              |None-> raise (Error (Printf.sprintf "current object does not have parent class : super out of reach" )) 
              |Some par ->
                let cls_methods = methods_list par [] in
                begin
                  match List.find_opt (fun m -> m.method_name= methname)  cls_methods with
                  |None -> assert false
                  |Some meth_def ->
                    (*evaluate each of the expression of our arguments and keeping them in a list*)
                      let param_val = List.map (fun expr -> eval expr) params in
                      eval_call meth_def (VObj obj) param_val 
                end
            end
          | _ -> 
            let obj = evalo e in
            let cls_methods = methods_list obj.cls [] in
            begin
              match List.find_opt (fun m -> m.method_name= methname)  cls_methods with
              |None -> assert false
              |Some meth_def ->
                (*evaluate each of the expression of our arguments and keeping them in a list*)
                  let param_val = List.map (fun expr -> eval expr) params in
                  eval_call meth_def (VObj obj) param_val 
            end
        end
      | This | Super -> 
        begin
          match (Hashtbl.find_opt lenv "this") with
          |Some v ->  v 
          |None-> raise (Error (Printf.sprintf "no current object can be attained" )) 
        end
      | NewCstr (s,params) -> 
        let obj = create_struct s in
        let cls_methods = methods_list obj.cls [] in
        begin
          match List.find_opt (fun m -> m.method_name= "constructor")  cls_methods with
          |None -> raise (Error (Printf.sprintf "the object has no constructor" ))
          |Some meth_def ->
            (*evaluate each of the expression of our arguments and keeping them in a list*)
            let param_val = List.map (fun expr -> eval expr) params in
            let b = !is_constructor in
            is_constructor := (true, obj.cls);
            let v = eval_call meth_def (VObj obj) param_val in 
            is_constructor := b ;
            if (v)<>Null 
              then raise (Error (Printf.sprintf "contructor must have no return " ))
            else
              VObj obj 
        end
      | InstanceOf(e,t) -> 
        begin
          if t=TVoid then VBool false
          else 
            try begin
            match eval e with
            |VObj obj -> VBool (t = (TClass obj.cls))
            |VInt _ -> VBool (t=TInt)
            |VBool _ -> VBool (t=TBool)
            |Null -> VBool (false) (*Null is not an instance of any type*)
            end
          with |_ -> VBool (false) (*same as java, for uninitialised variables instanceof is false *)
        end
    and eval_mem (m:mem_access): value = match m with
        |Var(s)-> 
          begin
            match (Hashtbl.find_opt lenv s), (Hashtbl.find_opt env s) with
            |None,None -> raise (Error (Printf.sprintf "there is no variable named %s" s)) 
            (*if we find  a variable by the name s we check if it has been initialised*)
            |Some v,_ -> if(v!=Null) then v (*a local var hides any global vars of the same name*)
                          else raise (Error (Printf.sprintf "the local variable named %s has not been initialised" s)) 
            |None, Some v -> if(v!=Null) then v 
                          else raise (Error (Printf.sprintf "the global variable named %s has not been initialised" s)) 
          end
        |Field(e,s) -> let o = eval e in 
        match o with
        |VBool _ | VInt _ | Null -> raise (Error (Printf.sprintf "the variable %s is not an object " s))
        |VObj obj ->
          begin
          match Hashtbl.find_opt (obj.fields) s with
          |None -> raise (Error (Printf.sprintf "this object does not have a field named %s" s))
          |Some f -> f
          end
    in
  
    let rec exec (i: instr): unit = match i with
      | Print e -> Printf.printf "%d\n" (evali e)
      | If(e,s1,s2) -> if (evalb e) then exec_seq s1 else exec_seq s2
      | While(e, s) -> begin 
            if (evalb e) then begin
              exec_seq s;
              exec (While(e,s))
            end
          end 
      | Set(m,e) -> 
        begin 
          match m with
          |Var(s) -> 
            begin
              let new_v = eval(e) in 
              begin
              match (Hashtbl.find_opt lenv s), (Hashtbl.find_opt env s) with
              |None,None -> raise (Error (Printf.sprintf "no variables by the name of %s exist" s))
              |Some old_v,_ -> Hashtbl.replace lenv s new_v    (*a local var hides any global vars of the same name*)
              |None, Some old_v -> Hashtbl.replace env s new_v 
              end
            end
          |Field(e1,s)-> let o = eval(e1) in
          match o with
          |VBool _ | VInt _ | Null -> raise (Error (Printf.sprintf "the variable %s is not an object " s))
          |VObj obj ->
            begin
            match Hashtbl.find_opt (obj.fields) s with
            |None -> raise (Error (Printf.sprintf "this object does not have a field named %s" s))
            |Some _ -> 
              let b = !is_constructor in
              if (is_final obj.cls s) && ((not (fst b))||(not (snd b = obj.cls)))
                then raise (Error (Printf.sprintf "the field %s is final you may not modify it outside of the constrcutor" s))
              else 
                let new_val = eval(e) in 
                Hashtbl.replace (obj.fields) s new_val
            end
        end
      | Return(e)-> 
        begin
          let new_v = eval e in 
          begin
            match (Hashtbl.find_opt lenv "call_result") with
            |Some old_v -> Hashtbl.replace lenv "call_result" new_v 
            |None -> raise (Error (Printf.sprintf "you cannot return outside of a method call"))
          end
        end
      | Expr(e) -> 
        let v = eval e in 
        if(v!=Null) then raise (Error (Printf.sprintf "expression used as instruction must be of type void"))
      | NewVar(s,t)-> 
        begin
          if  s = "call_result" then raise (Error (Printf.sprintf "you cannot name your variable %s, it represents a property in this langage" s))
          else
          match (Hashtbl.find_opt lenv s) with
          |Some t -> raise (Error (Printf.sprintf "a local variable of the name %s already exists" s))
          |None -> Hashtbl.add lenv s Null;  
        end
    and exec_seq s = 
      List.iter exec s
    in

    exec_seq s
  in
  
  exec_seq p.main (Hashtbl.create 1)
