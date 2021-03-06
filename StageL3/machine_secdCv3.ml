open String ;;
open Printf ;;
open List ;;
open Lang_secdC.ISWIM ;;


module SECDCv3Machine =
  struct




    (**** Types ****)

    (* Petits types très pratique pour ne pas se mélanger dans la compréhension des types suivants *)
    type id_signal  =   string
    type variable   =   string
    type id_thread  =   int
    type id_error   =   int
    type emit       =   bool
    type init       =   bool




    (**** Control string ****)

    (* type intermédiaire qui va servir à représenter la chaîne de contrôle *)
    type c =
        Constant of int                                         (* constante b               *)
      | Variable of variable                                    (* variable X                *)
      | Ap                                                      (* application               *)
      | Prim of operateur                                       (* opérateur                 *)
      | Pair of variable * c list                               (* abstraction               *)
      | Bspawn                                                  (* début du spawn            *)
      | Espawn                                                  (* fin du spawn              *)
      | Emit of id_signal                                       (* emet s                    *)
      | Present of id_signal * c list * c list                  (* present s in t1 t2        *)
      | Signal of id_signal * c list                            (* signal s in t             *)
      | Throw of id_error                                       (* lève l'erreur             *)
      | Catch of id_error * c list * (variable * c list)        (* try and catch classique   *)
      | Error of id_error                                       (* une erreur traitée        *)
      | Put of id_signal                                        (* place dans un signal      *)
      | Get of id_signal                                        (* prends dans un signal     *)

    (* Ce type représente la chaîne de contrôle de la machine SECD, c'est notre entrée *)
    type control_string = c list   


    

    (**** Environment ****)

    (* type intermédiaire qui va servir à représenter l'environnement *)
    type e =   
        EnvClos of (variable * (control_string * e list))     (* (X,(C,Env))                   *)
      | EnvVar  of (variable * control_string)                (* (X,V) V une constante/erreur  *)

    (* Ce type représente l'environnement de la machine SECD, c'est notre liste de substitution *)
    type environment = e list





    (**** Stack ****)

    (* type intermédiaire contenant une fermeture qui lie une abstraction à un environnement ou juste une constante ou encore une erreur *)
    type s =  
        Unit                                                  (* remplace             *)
      | Stack_const of int                                    (* constante            *)
      | Stack_error of id_error                               (* une erreur           *)
      | Closure of (control_string * environment)             (* fermeture (C,Env)    *)

    
    (* Ce type représente la pile de la machine SECD, c'est la où la machine travaille *)
    type stack = s list
    
    


    (**** Signals ****)

    (* type intermédiaire contenant pour un id de thread donné, sa liste de signaux qui ont eux même 
       leurs liste de valeurs, un booléen qui représente leurs initialisations et un autre leurs émissions *)
    type cs = CS of id_signal * (id_thread * int list * init) list * emit

    (* Ce type représente les signaux courants, c'est-à-dire, les signaux qui sont initialisé et émit à l'instant courant *)
    type current_signals = cs list

    (* type intermédiaire contenant pour un id de thread donné, sa liste de signaux qui ont eux mếme leurs liste de valeurs *)
    type ssi = SSI of id_signal * ((id_thread * ((int * (id_thread list)) list) * id_thread list ) list)

    (* Ce type représente les signaux partagés, c'est-à-dire, les signaux qui ont été émit à l'instant précédent *)
    type shared_signals = ssi list

    (* Les signaux sont regroupés dans un type qui est une pair comprenant 
       les signaux courants et les signaux partagés qui sont les signaux de l'instant précédent *)
    type signals = current_signals * shared_signals




    (**** Dump ****)

    (* Ce type représente le dépôt de la machine SECD, c'est-à-dire, l'endroit où l'on sauvegarde une partie de l'état 
       de la machine pour travailler sur une autre partie de la chaîne de contrôle *)
    type dump =
        Vide_D                                                                      (* le dépôt est vide      *)
      | Save       of stack * environment * control_string * dump                   (* (s,e,c,d)              *)
      | SaveSignal of id_signal * stack * environment * control_string * dump       (* (signal,s,e,c,d)       *)




    (**** Thread list ****)

    (* type intermédiaire représentant un thread, comprenant son identifiant, sa pile , son environnement, sa chaîne de contrôle et son dépôt *)
    type thread = Thread of id_thread * stack * environment * control_string * dump

    (* Ce type représente la file d'attente de la machine SECD version concurrente, c'est-à-dire, 
       la file contenant les threads qui doivent être traité dans l'instant courant *)
    type wait = thread list

    (* Ce type représente la file de thread bloqués de la machine SECD version concurrente, c'est-à-dire, 
       la file contenant les threads qui sont en attente d'un signal ou juste de la fin de l'instant courant *)
    type stuck = (id_signal * thread) list

    (* Ce type représente l'ensemble des threads en cours de la machine SECD version concurrente. Cette ensemble est divisé en deux dans une pair, 
       d'un côté la liste d'attente de leurs tours et de l'autre la lite de threads bloqués *)
    type thread_list = wait * stuck


    

    (**** Identifier producer ****)

    (* Ce type représente un producteur d'identifiant de la machine SECD version concurrente, c'est-à-dire,
       un entier qui va donné un identifiant unique à chaque thread et s'incrémenter *)
    type identifier_producer = int




    (**** Handler ****)

    (* Ce type représente le gestionnaire de la machine SECD, c'est-à-dire, 
       l'endroit où l'on met une sauvegarde complète de la machine quand on a un try and catch *)
    type handler = 
        Vide_H                                                (* le handler est vide        *)
      | SaveHandler of id_error            *                  (* (erreur,(id,s,e,c,d,h,ip)) *)
                                              (
                       id_thread           * 
                       stack               * 
                       environment         * 
                       control_string      *
                       dump                * 
                       thread_list         * 
                       signals             * 
                       handler             *
                       identifier_producer    ) 


    

    (**** Machine SECD version concurrente 3 ****)

    (* Ce type représente la structure de la machine SECD version concurrente 3 *)
    type secdCv3 = Machine of  id_thread           * 
                               stack               * 
                               environment         * 
                               control_string      * 
                               dump                * 
                               thread_list         * 
                               signals             * 
                               handler             *
                               identifier_producer 










    (**** Exception ****)

    exception NoSubPossible                    (* Aucune substitution possible pour cette variable dans l'environnement             *)
    exception StrangeEnd                       (* Même moi je ne sais pas ce qu'il sait passé ...                                   *)
    exception EndSpawnNotFound                 (* La délimitation de fin du spawn n'est pas trouvé dans la chaîne de contrôle       *)
    exception NoSharedValues                   (* Il n'y a pas de valeurs partagées                                                 *)

    exception NotAllConstants                  (* Tous les éléments de la pile prisent pour l'opérateurs ne sont pas des constantes *)
    exception InsufficientOperandNb            (* Le nombre d'opérande est insuffisante par rapport au nombre requis                *)
    exception ImpossibleResult                 (* Le résultat n'est pas dans un format autorisé, soit un entier ou une abstraction  *)

    exception SignalAlreadyInit                (* Le signal est déjà initialisé dans ce thread                                      *)
    exception SignalAlreadyEmit                (* Le signal est déjà émit dans la machine                                           *)
    exception SignalNotInit                    (* Le signal n'est pas initialisé dans ce thread                                     *)
    exception SignalNotShared                  (* Le signal n'est pas dans la liste des signaux partagés                            *)
    exception ThreadSharedNotFound             (* L'identifiant de thread lié à un signal n'existe pas                              *)
    exception PointerNotExist                  (* Le pointeur n'existe pas                                                          *)

    exception UnknowState                      (* Le format de la machine est invalide et/ou inconnu                                *)
    exception UnknowStackState                 (* Le format de la pile est invalide et/ou inconnu                                   *)
    exception UnknowEnvState                   (* Le format de l'environnement est invalide et/ou inconnu                           *)
    exception UnknowWaitState                  (* Le format de la liste d'attente est invalide et/ou inconnu                        *)
    exception UnknowStuckState                 (* Le format de la liste d'élément bloqués est invalide et/ou inconnu                *)
    exception UnknowDumpState                  (* Le format du dépôt est invalide et/ou inconnu                                     *)
    exception UnknowHandlerState               (* Le format du gestionnaire d'erreur est invalide et/ou inconnu                     *)
    exception UnknowSSIState                   (* Le format de la liste de signaux partagés est invalide                            *)

    exception BadVersion








    (**** Affichage ****)

    (* Convertit une chaîne de caractère en chaîne de caractère (utilisée pour faire un affichage générique) *)
    let string_of_string elem = elem


    (* Convertit une liste en chaîne de caractère *)
    let rec string_of_a_list string_of_a l inter =
      match l with
        | []    ->   ""
        | [h]   ->   (string_of_a h)
        | h::t  ->   (string_of_a h)^inter^(string_of_a_list string_of_a t inter)


    (* Convertit le langage ISWIM en langage SECD *)
    let rec secdLanguage_of_exprISWIM expression =
      match expression with
          Lang_secdC.ISWIM.Const const                     ->   [Constant const]
          
        | Lang_secdC.ISWIM.Var var                         ->   [Variable var]
          
        | Lang_secdC.ISWIM.App(expr1,expr2)                ->   append (  append (secdLanguage_of_exprISWIM expr1) (secdLanguage_of_exprISWIM expr2)) [Ap]
          
        | Lang_secdC.ISWIM.Op(op,liste_expr)               ->   append ( flatten( map secdLanguage_of_exprISWIM liste_expr)) [(Prim(op))]
          
        | Lang_secdC.ISWIM.Abs(abs,expr)                   ->   [Pair(abs,(secdLanguage_of_exprISWIM expr))]

        | Lang_secdC.ISWIM.Spawn expr                      ->   append [Bspawn] (append (secdLanguage_of_exprISWIM expr) [Espawn])

        | Lang_secdC.ISWIM.Present (signal,expr1,expr2)    ->   [Present (signal,(secdLanguage_of_exprISWIM expr1),(secdLanguage_of_exprISWIM expr2))]

        | Lang_secdC.ISWIM.Emit signal                     ->   [Emit (signal)]

        | Lang_secdC.ISWIM.InitFor (signal,expr)           ->   [Signal (signal,(secdLanguage_of_exprISWIM expr))]

        | Lang_secdC.ISWIM.Throw error                     ->   [Throw(error)]

        | Lang_secdC.ISWIM.Catch(error,expr1,(abs,expr2))  ->   [Catch(error,(secdLanguage_of_exprISWIM expr1),(abs,(secdLanguage_of_exprISWIM expr2)))]

        | Lang_secdC.ISWIM.Put(signal,value)               ->   [Constant value ; Put(signal)]

        | Lang_secdC.ISWIM.Get(signal,id_thread)           ->   [Constant id_thread ;Get(signal)]

        | _                                                ->   raise BadVersion


    (* Donne une chaîne de caractères contenant un message d'erreur par rapport à l'identifiant de l'erreur *)
    let error_message error =
      match error with
          0   ->  "ERREUR : Etrange..."                                           (* StrangeEnd            *)

        | 1   ->   "ERREUR : Format de la machine invalide :/"                   (* UnknowState           *)
        | 2   ->   "ERREUR : Format de la liste bloqué invalide"                 (* UnknowStuckState      *)
        | 3   ->   "ERREUR : Format de la liste d'attente invalide"              (* UnknowWaitState       *) 
        | 4   ->   "ERREUR : Format de l'environnement invalide"                 (* UnknowEnvState        *)
        | 5   ->   "ERREUR : Format de la pile invalide"                         (* UnknowStackState      *)
        | 6   ->   "ERREUR : Format du dépôt invalide"                           (* UnknowDumpState       *)
        | 7   ->   "ERREUR : Format du gestionnaire invalide"                    (* UnknowHandlerState    *)

        | 8   ->   "ERREUR : Signal non initialisé"                              (* SignalNotInit         *)
        | 9   ->   "ERREUR : Signal déjà initialisé"                             (* SignalAlreadyInit     *)
        
        | 10  ->   "ERREUR : Aucune substitution possible"                       (* NoSubPossible         *)

        | 11  ->   "ERREUR : Le format du spawn est invalide"                    (* EndSpawnNotFound      *)

        | 12  ->   "ERREUR : Ce ne sont pas tous des constantes"                 (* NotAllConstants       *)
        | 14  ->   "ERREUR : Nombre d'opérande insuffisant"                      (* InsufficientOperandNb *)
        | 15  ->   "ERREUR : Format de l'opérateur invalid"                      (* OpFormatError         *)
        | 16  ->   "ERREUR : Résultat impossible"                                (* ImpossibleResult      *)

        | 17  ->   "ERREUR : Aucune valeurs partagées"                           (* NoSharedValues        *)
        | 18  ->   "ERREUR : Le signal n'a pas été partagé"                      (* SignalNotShared       *)
        | 20  ->   "ERREUR : Le thread n'est pas trouvé"                         (* ThreadSharedNotFound  *)
        | 21  ->   "ERREUR : Le pointeur n'existe pas"                           (* PointerNotExist       *)

        | _   ->   "ERREUR : Cette erreur n'existe pas "


    (* Convertit la chaîne de contrôle en une chaîne de caractères *)
    let rec string_of_control_string expression =
      let string_of_cs_element element =
        match element with
          | Constant const                  ->   (string_of_int const)
        
          | Variable var                    ->   var
        
          | Ap                              ->   "AP"
        
          | Pair(abs,expr_list)             ->   "<"^abs^","^(string_of_control_string expr_list)^">"
        
          | Prim op                         ->   "PRIM "^(string_of_operateur op)

          | Bspawn                          ->   "BSPAWN"

          | Espawn                          ->   "ESPAWN"

          | Present(signal,expr1,expr2)     ->   "PRESENT "^signal^" IN "^(string_of_control_string expr1)^(string_of_control_string expr2)

          | Emit signal                     ->   "EMIT "^signal

          | Signal(signal,expr)             ->   "SIGNAL "^signal^" IN "^(string_of_control_string expr)

          | Throw error                     ->   (error_message error)

          | Catch(error,expr1,(abs,expr2))  ->    "TRY "^(string_of_control_string expr1)^"CATCH "^(error_message error)
                                                  ^" IN <"^abs^" , "^(string_of_control_string expr2)^">" 

          | Error error                     ->   (error_message error)

          | Put signal                      ->   signal^" PUT"

          | Get signal                      ->   signal^" GET"

      in string_of_a_list string_of_cs_element expression " "


    (* Convertit un environnement en chaîne de caractères *)
    let rec string_of_environment environment =
      let aux element = 
        match element with
          | EnvClos(var,(control_string,env))  ->   "["^var^" , ["^(string_of_control_string control_string) ^" , "^(string_of_environment env)^"]]"

          | EnvVar(var,control_string)         ->   "["^var^" , "^(string_of_control_string control_string) ^"]"
      in string_of_a_list aux environment " , "


    (* Convertit une pile en chaîne de caractères *)
    let rec string_of_stack stack =
      match stack with
          []                                ->   ""

        | Unit::t                           ->   "Unit "^(string_of_stack t)

        | Stack_const b::t                  ->   (string_of_int b)^" "^(string_of_stack t)

        | Stack_error e::t                  ->   "Erreur "^(string_of_int e)^" "^(string_of_stack t)

        | (Closure(control_string,env))::t  ->   "["^(string_of_control_string control_string)^" , {"^(string_of_environment env)^"}]"^(string_of_stack t)
        

    (* Convertit la sauvegarde en chaîne de caractères *)
    let rec string_of_dump dump =
      match dump with 
          Vide_D                                            ->   ""

        | Save(stack,env,control_string,dump)               ->    "("^(string_of_stack stack)^" , "^(string_of_environment env)^" , "
                                                                 ^(string_of_control_string control_string)^" , "^(string_of_dump dump)^")"

        | SaveSignal(signal,stack,env,control_string,dump)  ->    "("^signal^" , "^(string_of_stack stack)^" , "^(string_of_environment env)^" , "
                                                                 ^(string_of_control_string control_string)^" , "^(string_of_dump dump)^")"
        

      
    (* Convertit un thread en chaîne de caractères *)
    let string_of_thread thread =
      match thread with
        Thread(id,stack,env,control_string,dump)  ->    "("^(string_of_int id)^" , "^(string_of_stack stack)^" , "
                                                       ^(string_of_environment env)^" , "^(string_of_control_string control_string)^" , "
                                                       ^(string_of_dump dump)^")"


    (* Convertit la liste des éléments en attente en chaîne de caractères *)
    let string_of_wait wait = string_of_a_list string_of_thread wait " , "


    (* Convertit la liste des éléments bloqués en chaîne de caractères *)
    let string_of_stuck stuck =
      let aux element =
        match element with 
          | (signal,thread)   ->   "( "^signal^", "^(string_of_thread thread)^" )"
      in string_of_a_list aux stuck " , "


    (* Convertit la liste des threads en chaîne de caractères *)
    let string_of_thread_list thread_list =
      match thread_list with
        (wait,stuck)  ->    "\n     WAIT    : "^(string_of_wait wait)
                           ^"\n     STUCK   : "^(string_of_stuck stuck)

    
    

    (* Convertit une liste de signaux courant en chaîne de caractères *)
    let string_of_cs cs_list =
      let aux  element = 
        match element with
          | (id_thread,values,init)       ->    "("^(string_of_int id_thread)^",{"^(string_of_a_list string_of_int values " ")^"},"^(string_of_bool init)^")"
      in string_of_a_list aux cs_list " "


    (* Convertit la liste des signaux courant liés à leurs threads en chaîne de caractères *)
    let string_of_current_signals current_signals =
      let aux element =
        match element with
          | CS(id_signal,thread_list,emit)   ->   "["^id_signal^" : {"^(string_of_cs thread_list)^","^(string_of_bool emit)^"}]"
      in string_of_a_list aux current_signals " ; "


    (* Convertit la liste des signaux partagés en chaîne de caractères *)
    let string_of_ssi ssi_list = 
      let aux1 element =
        let aux values =
          match values with
            | (value,pointers)                ->   "("^( string_of_int value)^",{"^(string_of_a_list string_of_int pointers " ")^"})"
        in
        match element with
          | (id_thread,values,thread_list)    ->   " ("^(string_of_int id_thread)^",["^(string_of_a_list aux values ";")
                                                  ^"],{"^(string_of_a_list string_of_int thread_list " ")^"})"
      in string_of_a_list aux1 ssi_list " "

    
    (* Convertit la liste des signaux partagés lié à leurs threads en chaîne de caractères *)
    let string_of_shared_signals shared_signals =
      let aux element = 
        match element with
          | SSI(id_signal,thread_list)   ->   "["^id_signal^" : {"^(string_of_ssi thread_list)^"}]"
      in string_of_a_list aux shared_signals " , "


    (* Convertit la liste de tous les signaux en chaîne de caractères *)
    let string_of_signals signals =
      match signals with
        (current_signals,shared_signals)  ->    "\n     CURRENT  : "^(string_of_current_signals current_signals)
                                               ^"\n     SHARED   : "^(string_of_shared_signals shared_signals)

    
    (* Convertit le gestionnaire en chaîne de caractères *)
    let rec string_of_handler handler =
      match handler with
          Vide_H                                                                                                 ->   ""
        
        | SaveHandler(error,(id,stack,env,control_string,dump,thread_list,signals,handler,identifier_producer))  ->    
                                        "\n      ERREUR  : "^(error_message error)
                                       ^"\n      ID      : "^(string_of_int id)
                                       ^"\n      STACK   : "^(string_of_stack stack)
                                       ^"\n      ENV     : "^(string_of_environment env)
                                       ^"\n      CONTROL : "^(string_of_control_string control_string)
                                       ^"\n      DUMP    : "^(string_of_dump dump)
                                       ^"\n      THREADS : "^(string_of_thread_list thread_list)
                                       ^"\n      SIGNALS : "^(string_of_signals signals)
                                       ^"\n      HANDLER : "^(string_of_handler handler)
                                       ^"\n      IP      : "^(string_of_int identifier_producer)
                                       ^"\n"


    (* Convertit une machine SECD en chaîne de caractères *)
    let string_of_secdMachine machine =
      match machine with
        Machine(id,stack,env,control_string,dump,thread_list,signals,handler,identifier_producer)  ->    
                                        "\n   ID      : "^(string_of_int id)
                                       ^"\n   STACK   : "^(string_of_stack stack)
                                       ^"\n   ENV     : "^(string_of_environment env)
                                       ^"\n   CONTROL : "^(string_of_control_string control_string)
                                       ^"\n   DUMP    : "^(string_of_dump dump)
                                       ^"\n   THREADS : "^(string_of_thread_list thread_list)
                                       ^"\n   SIGNALS : "^(string_of_signals signals)
                                       ^"\n   HANDLER : "^(string_of_handler handler)
                                       ^"\n   IP      : "^(string_of_int identifier_producer)
                                       ^"\n\n"


    (* Affiche la machine SECD concurrente version 3 *)
    let afficherSECDCv3 machine = printf "MachineSECDCv3 : %s\n" (string_of_secdMachine machine)










    (**** Fonctions utiles ****)

    (* Substitue une variable à sa fermeture liée *)
    let rec substitution x env =
      match env with
          []                                    ->   raise NoSubPossible

        | EnvClos(var,(control_string,env))::t  ->   if (equal x var) then  Closure(control_string,env) else substitution x t

        | EnvVar(var,control_string)::t         ->   if (equal x var) 
                                                      then 
                                                        begin
                                                          match control_string with
                                                              [Constant b]  ->   Stack_const b 
                                                            
                                                            | [Error e]     ->   Stack_error e

                                                            | _             ->   raise UnknowEnvState
                                                        end
                                                      else substitution x t
        


    (* Convertit une liste d'éléments de la pile contenant des constantes en liste d'entiers *)
    let rec convert_stack_element_to_int_list stack nbrOperande =
      match (stack,nbrOperande) with
          (_,0)                       ->   []

        | (Stack_const b::t,nbr)      ->   b::(convert_stack_element_to_int_list t (nbr - 1)) 

        | (_,nbr)                     ->   if nbr = 0 then raise NotAllConstants else raise FormatOpErreur


    (* Retire un nombre n d'élément de la pile *)
    let rec remove_elements stack nbrOperand =
      match (stack,nbrOperand) with
          (stack,0)   ->   stack

        | (_::t,nbr)  ->   if nbr > 0 then remove_elements t (nbr - 1) else raise InsufficientOperandNb

        | ([],_)      ->   raise InsufficientOperandNb


    
    (* Retourne la liste des signaux courant par rapport à un identifiant d'un thread *)
    let rec give_signals current_signals signal=
      match current_signals with
          []                     ->   []
  
        | CS(signal1,threads,_)::t     ->   if (signal = signal1) then threads else (give_signals t signal)
      


    (* Vérifie si c'est un init *)
    let isInit signals id signal =
      let rec aux threads =
        match threads with
            []               ->   false

          | (id1,_,init)::t  ->   if (id = id1) then init else aux t
      in
      let temp = (give_signals signals signal) in  aux temp


    (* Vérifie si c'est une émission *)
    let rec isEmit current_signals signal =
      match current_signals with
          []                     ->   false

        | CS(signal1,_,emit)::t  ->   if (signal = signal1) then emit else isEmit t signal

      
    (* Ajoute une  fermeture à l'environnement *)
    let rec add_env env varToRep stack_element =
      match stack_element with
          Stack_const(b)                ->    begin
                                                match env with
                                                    [] -> [EnvVar(varToRep,[Constant b])]

                                                  | EnvClos(var1,closure)::t -> if (equal var1 varToRep) then append [EnvVar(varToRep,[Constant b])] t 
                                                                                                         else append [EnvClos(var1,closure)] (add_env t varToRep stack_element)

                                                  | EnvVar(var1,control_string)::t -> if (equal var1 varToRep) then append [EnvVar(varToRep,[Constant b])] t 
                                                                                                               else append [EnvVar(var1,control_string)] (add_env t varToRep stack_element)
                                              end

      | Stack_error(error)              ->    begin 
                                                match env with
                                                    [] -> [EnvVar(varToRep,[Error error])]

                                                  | EnvClos(var1,closure)::t -> if (equal var1 varToRep) then append [EnvVar(varToRep,[Error error])] t 
                                                                                                         else append [EnvClos(var1,closure)] (add_env t varToRep stack_element)

                                                  | EnvVar(var1,control_string)::t -> if (equal var1 varToRep) then append [EnvVar(varToRep,[Error error])] t 
                                                                                                               else append [EnvVar(var1,control_string)] (add_env t varToRep stack_element)
                                              end

        | Closure(control_string,env1)  ->   begin
                                              match env with
                                                    [] -> [EnvClos(varToRep,(control_string,env1))]

                                                  | EnvClos(var1,closure)::t -> if (equal var1 varToRep) then append [EnvClos(varToRep,(control_string,env1))] t 
                                                                                                         else append [EnvClos(var1,closure)] (add_env t varToRep stack_element)

                                                  | EnvVar(var1,control_string1)::t -> if (equal var1 varToRep) then append [EnvClos(varToRep,(control_string,env1))] t 
                                                                                                                else append [EnvVar(var1,control_string)] (add_env t varToRep stack_element)
                                              end

        | _                             ->   raise UnknowStackState


    (* Ajoute un signal initialisé dans l'environnement *)
    let rec add_init_signal current_signals id signal = 
      let rec aux1 threads =
        match threads with
            (id1,values,init)::t                  ->   if (id = id1) then append [(id,values,true)] t else append [(id1,values,init)] (aux1 t)

          | []                                    ->   [(id,[],true)]
      in
      if (isInit current_signals id signal) 
        then raise SignalAlreadyInit
        else  match current_signals with
                  CS(signal1,threads,emit)::t   ->   if (signal = signal1) then (append [CS(signal,(aux1 threads),emit)] t) else (append [CS(signal1,threads,emit)] (add_init_signal t id signal))
          
                | []                            ->   [CS(signal,[(id,[],true)],false)]


    (* Prend la partie de la chaîne pour le thread et la retire de la chaîne de contrôle *)
    let rec spawn control_string = 
      match control_string with
          []         -> raise EndSpawnNotFound

        | Espawn::t  ->   ([],t)

        | h::t       ->   let (recover,remove) = spawn t in (h::recover,remove)

 
    (* Dans le cas où le signal attendu n'est pas emit on applique le second choix*)
    let end_of_the_moment_thread thread_list =
      let rec aux stuck =
        match stuck with
            []                                              ->   []

          | (_,Thread(id,s,e,((Present(_,_,c2))::c),d))::t  ->   (Thread( id , s , e , (append c2 c) , d ))::(aux t)

          | _                                               ->   raise UnknowStuckState
      in
      match thread_list with
        (_,stuck)                                        ->   ((aux stuck),[]) 


    (* Remet à zero les signaux en vidant la liste des valeurs et en mettant l'émission à faux *)
    let rec reset_current_signals current_signals =
      let rec aux thread_list =
        match thread_list with
            []                            ->   []

          | (thread,_,init)::t            ->   (thread,[],init)::(aux t)
      in
      match current_signals with
          []                              ->   []

        | CS(signal,thread_list,_)::t  ->   CS(signal,(aux thread_list),false)::(reset_current_signals t)


    (* Prends les signaux dans la liste des signaux courants et les mets dans la liste des signaux partagés *)
    let rec share current_signals =
      let rec aux thread_list =
        match thread_list with
            []                             ->   []

          | (thread,values,_)::t           ->   (thread,(map (fun x -> (x,[])) values),[])::(aux t)
      in
      match current_signals with
          []                               ->   []

        | CS(signal,thread_list,true)::t   ->   SSI(signal,(aux thread_list))::(share t)

        | CS(_,_,false)::t                 ->  (share t)


    (* Quand l'instant est fini ont remet à zéro les signaux courant et on change les signaux partagés *)
    let end_of_the_moment_signals signals =
      match signals with
        (current_signals,_)  ->   ((reset_current_signals current_signals),(share current_signals)) 


    (* Prend les threads réveillés et les retire de la liste des threads bloqués *)
    let rec reaction_of_signal signal stuck =
      match stuck with 
          [] -> ([],[])

        | (signal1,thread)::t -> let (awake,still_stuck) = reaction_of_signal signal t in 
                                  if (equal signal signal1) then (append awake [thread],still_stuck) else (awake,append still_stuck [(signal1,thread)])


    (* Applique les effets d'une émission sur la liste des threads *)
    let reaction signal tl =
      match tl with 
        (w,st) -> let (new_w,new_st) = reaction_of_signal signal st  in (append w new_w,new_st)

    (* Mets vrai pour l'émission du signal dans liste de signaux *)
    let rec emit_signal current_signals id signal =
      if isInit current_signals id signal
        then match current_signals with

                CS(signal1,threads,emit)::t  ->   if (signal = signal1) then (append [CS(signal1,threads,true)]  t) else (append [CS(signal1,threads,emit)]  (emit_signal t id signal))
                
              | []                           ->   raise SignalNotInit  

          else raise SignalNotInit


    (* Donne la pile avec le calcul fait *)
    let calculate operator stack environment = 
      let operand_number = getNbrOperande operator in
      let result = calcul operator (rev (convert_stack_element_to_int_list stack operand_number)) in
      match result with
          Abs(abs,expr)  ->   Closure((secdLanguage_of_exprISWIM (Abs(abs,expr))),environment)::(remove_elements stack operand_number) 

        | Const b        ->   Stack_const b::(remove_elements stack operand_number) 

        | _              ->   raise ImpossibleResult


    (* Mets à faux l'initilisation du signal dans la liste des signaux *)
    let rec remove_init_signal current_signals id signal =
      let rec aux1 threads =
        match threads with
            (id1,values,init)::t            ->   if (id = id1) then (append [(id1,values,false)]  t) else (append [(id1,values,init)]  (aux1 t))

          | []                              ->   raise SignalNotInit
        in
      match current_signals with
          CS(signal1,threads,emit)::t     ->   if (signal = signal1) then (append [CS(signal1,(aux1 threads),emit)]  t) else (append [CS(signal1,threads,emit)] (remove_init_signal t id signal))
          
        | []                              ->   raise SignalNotInit

    
    (* Ajoute un élément dans la liste des variables liés au signal et à l'id du thread courant *)
    let rec put current_signal signal id b = 
      let rec aux1 signals =
        match signals with
          (id1,values,true)::t     ->   if (id = id1) then (append [(id1,(append values [b]),true)] t) else (append [(id1,values,true)]  (aux1 t))

        | (id1,values,false)::t    ->   if (id = id1) then raise SignalNotInit else (append [(id1,values,false)]  (aux1 t))

        | []                       ->   raise SignalNotInit
      in
      match current_signal with
          CS(signal1,threads,emit)::t  ->   if (signal = signal1) then (append [CS(signal1,(aux1 threads),emit)]  t) else (append [CS(signal1,threads,emit)] (put t signal id b))

        | []                           ->   raise SignalNotInit


    (* Copie l'état d'un signal pour un thread donné  pour un nouveau thread*)
    let rec clone id_current_thread id_new_thread current_signals =
      let rec aux1 threads =
        match threads with
            []                          ->   []

          | (id,values,init)::t         ->   if (id = id_current_thread) then  append [(id,values,init);(id_new_thread,values,init)] t else append [(id,values,init)] (aux1 t)
      in
      match current_signals with
          CS(signal,threads,emit)::t  ->   CS(signal,(aux1 threads),emit)::(clone id_current_thread id_new_thread t)

        | []                          ->   []


    (* Vérifie si c'est la première fois que l'on pioche dans une liste de valeurs *)
    let rec first_get id_thread values =
      match values with
          []                     ->   true

        | (_,pointers)::t        ->   if (mem id_thread pointers) then false else first_get id_thread t

    
    (* Ajoute un pointeur dans une liste de pointeurs *)
    let addIt it pointers = append pointers [it]


    (* Retire un pointeur d'une liste de pointeurs *)
    let removeIt it pointers =
      let rec aux pointers =
        match pointers with
            []    ->   []

          | h::t  ->   if (h = it) then aux t else h::(aux t)
      in
      if (mem it pointers) then aux pointers else raise PointerNotExist


    (* Retourne la valeur présent dans la liste de valeurs partagés lié au signal et à l'identifant donné 
       qui est la suivante de celle pointé part le pointeurs lié à ton thread *)    
    let get signals id_thread signal my_thread =
      let rec aux3 values =
        match values with
            []                       ->   raise UnknowSSIState

          | (value,pointers)::t      ->   (append [(value,(addIt my_thread pointers))] t)
      in
      let rec aux2 values =
        match values with
            []                       ->   raise UnknowSSIState

          | [(value,pointers)]       ->   if (mem my_thread pointers) 
                                            then (Stack_const value,[(value,(removeIt my_thread pointers))],true) 
                                            else raise UnknowSSIState

          | (value,pointers)::t      ->   if (mem my_thread pointers) 
                                            then let new_values               =   aux3 t in (Stack_const value,(append [(value,(removeIt my_thread pointers))] new_values),false) 
                                            else let (res,new_values,end_it)  =   aux2 t in (res,(append [(value,pointers)] new_values),end_it)
      in
      let rec aux1 threads =
        match threads with 
          
            (id,values,end_list)::t  ->   if (id = id_thread) 
                                            then if(mem my_thread end_list)
                                                    then (Unit,append [(id,values,end_list)] t)
                                                    else if(first_get my_thread values) 
                                                            then  match values with 
                                                                      (value,pointers)::t1  ->   (Stack_const value,append [(id,append [(value,pointers)] (aux3 t1),end_list)] t) 
                                                                    | []                    ->   (Unit,append [(id,[],append [my_thread] end_list)] t)
                                                            else let (res,new_values,end_it)   =   aux2 values in 
                                                                                                        if end_it 
                                                                                                          then (res,append [(id,new_values,append [my_thread] end_list)] t)
                                                                                                          else (res,append [(id,new_values,end_list)] t) 

                                            else   let (res,new_threads)  =   aux1 t      in (res,append [(id,values,end_list)] new_threads)

          | [] -> raise ThreadSharedNotFound
      in
      let rec aux shared_signals = 
        match shared_signals with
            []                       ->   raise SignalNotShared

          | SSI(signal1,threads)::t  ->   if (signal1 = signal) 
                                            then let (res,new_threads)  =   aux1 threads in (res,(append [SSI(signal1,new_threads)]       t))  
                                            else let (res,new_ssi)      =   aux t        in (res,(append [SSI(signal1,threads)    ] new_ssi)) 
      in
      match signals with
          (cs,[])                     ->   raise NoSharedValues

        | (cs,ssi)                    ->   let (res,new_ssi) = aux ssi in (res,(cs,new_ssi))









        
    (**** Machine SECD concurrente version 3 ****)

    (* Applique les règles de la machine SECD concurrente version 3 en affichant les étapes *)
    let transition machine =
      match machine with

          (* Constante *)
        | Machine(id,s,e,Constant b::c,d,tl,si,h,ip)                          ->   Machine( id , Stack_const b::s , e , c , d , tl , si , h , ip )


          (* Substitution *)
        | Machine(id,s,e,Variable x::c,d,tl,si,h,ip)                          
          ->    begin 
                  try   Machine( id , (substitution x e)::s , e , c , d , tl , si , h , ip ) 
                  with  NoSubPossible  ->  Machine( id , s , e , Throw 10::c , d , tl , si , h , ip )
                end


          (* Erreur *)
        | Machine(id,s,e,Error error::c,d,tl,si,h,ip)                         ->   Machine( id , Stack_error error::s , e , c , d , tl , si , h , ip )


          (* Opération *)
        | Machine(id,s,e,Prim op::c,d,tl,si,h,ip)                             
          ->    begin
                  try     Machine( id , (calculate op s e) , e , c , d , tl , si , h , ip )
                  with    NotAllConstants        ->   Machine( id , s , e , Throw 12::c , d , tl , si , h , ip )

                        | FormatOpErreur         ->   Machine( id , s , e , Throw 15::c , d , tl , si , h , ip )

                        | InsufficientOperandNb  ->   Machine( id , s , e , Throw 14::c , d , tl , si , h , ip )
                end


          (* Abstraction *)
        | Machine(id,s,e,Pair(abs,c1)::c,d,tl,si,h,ip)                        ->   Machine( id , Closure([Pair(abs,c1)],e)::s , e , c , d , tl , si , h , ip )
        

          (* Erreur levée *)
        | Machine(id,s,e,Throw error::c,d,tl,si,SaveHandler(id_error,(id1,s1,e1,Pair(abs,c2)::c1,d1,tl1,si1,h,ip1)),ip)                     
          ->    if (id_error = error) then  Machine( id1 , s1 , e1 , Pair(abs,c2)::Error error::Ap::c1, d1 , tl1 , si1 , h , ip1 )
                                      else  Machine( id , s , e , Throw error::c , d , tl , si , h , ip )


          (* Erreur levée non gérée *)
        | Machine(id,s,e,Throw error::c,tl,si,d,Vide_H,ip) -> Machine( id , [] , [] , [Throw error] , Vide_D , ([],[]) , ([],[]) , Vide_H , ip )
        

          (* Gestion des erreurs *)
        | Machine(id,s,e,Catch(error,c1,(abs,c2))::c,d,tl,si,h,ip)            
          ->    Machine( id , Unit::s , e , (append c1 c) , d , tl , si , SaveHandler(error,(id,s,e,(append [Pair(abs,c2)] c),d,tl,si,h,ip)) , ip )


          (* Création d'un thread *)
        | Machine(id,s,e,Bspawn::c,d,(w,st),(cs,ssi),h,ip)                          
          ->    begin 
                  try   let (cs_recover,cs_remove) = spawn c in Machine( id , Unit::s , e , cs_remove , d , (append w [Thread(ip,s,e,cs_recover,d)],st) , ((clone id ip cs),ssi) , h , (ip+1) )
                  with  EndSpawnNotFound  ->   Machine( id , s , e , Throw 11::c , d , (w,st) , (cs,ssi) , h , ip )
                end


          (* Ajout d'une valeur *)
        | Machine(id,Stack_const b::s,e,Put signal::c,d,tl,(cs,ssi),h,ip)           
          ->    begin
                  try   Machine( id , Unit::s , e , c , d , tl , ((put cs signal id b),ssi) , h , ip )
                  with  SignalNotInit  ->   Machine( id , s , e , Throw 8::c , d , tl , (cs,ssi) , h , ip ) 
                end


          (* Prise d'une valeur *)
        | Machine(id,Stack_const b::s,e,Get signal::c,d,tl,si,h,ip)           
          ->    begin
                  try   let (res,new_si) = get si b signal id in Machine( id , res::s , e , c , d , tl , new_si , h , ip )
                  with    NoSharedValues        ->   Machine( id , s , e , Throw 17::c , d , tl , si , h , ip ) 

                        | SignalNotShared       ->   Machine( id , s , e , Throw 18::c , d , tl , si , h , ip )

                        | ThreadSharedNotFound  ->   Machine( id , s , e , Throw 19::c , d , tl , si , h , ip )

                        | PointerNotExist       ->   Machine( id , s , e , Throw 21::c , d , tl , si , h , ip )
                end
                   
                
          (* Application *)
        | Machine(id,v::Closure([Pair(abs,c1)],e1)::s,e,Ap::c,d,tl,si,h,ip)   ->   Machine( id , [] , (add_env e1 abs v) , c1 , Save(s,e,c,d) , tl , si , h , ip )


          (* Application neutre droite *)
        | Machine(id,v::Unit::s,e,Ap::c,d,tl,si,h,ip)                         ->   Machine( id , v::s , e , c , d , tl , si , h , ip )
              

          (* Application neutre gauche *)       
        | Machine(id,Unit::v::s,e,Ap::c,d,tl,si,h,ip)                         ->   Machine( id , v::s , e , c , d , tl , si , h , ip )   
         

          (* Récupération sauvegarde *)
        | Machine(id,v::s,e,[],Save(s1,e1,c,d),tl,si,h,ip)                    ->   Machine( id , v::s1 , e1 , c , d , tl , si , h , ip )


          (* Récupération sauvegarde signal *)                             
        | Machine(id,v::s,e,[],SaveSignal(signal,s1,e1,c,d),tl,(cs,ssi),h,ip)       
          ->    begin
                  try   Machine( id , v::s1 , e1 , c , d , tl , ((remove_init_signal cs id signal ),ssi) , h , ip )
                  with  SignalNotInit  ->   Machine( id , s , e , Throw 8::c , d , tl , (cs,ssi) , h , ip )
                end


          (* Initialisation d'un signal *)
        | Machine(id,s,e,Signal(signal,c1)::c,d,tl,(cs,ssi),h,ip)                   
          ->    begin
                  try   Machine( id , [] , e , c1 , SaveSignal(signal,s,e,c,d) , tl , ((add_init_signal cs id signal),ssi) , h , ip )
                  with  SignalAlreadyInit  ->   Machine( id , s , e , Throw 9::c , d , tl , (cs,ssi) , h , ip )
                end


          (* Test de présence *)
        | Machine(id,s,e,Present(signal,c1,c2)::c,d,tl,(cs,ssi),h,ip)               
          ->    if (isInit cs id signal)
                  then if (isEmit cs signal)
                          then Machine( id , Unit::s , e , (append c1 c) , d , tl , (cs,ssi) , h , ip )

                          else match tl with
                                  ([],st)                          ->   Machine( ip , [] , [] , [] , Vide_D , ([],(append st [(signal,Thread(id,s,e,Present(signal,c1,c2)::c,d))])) , (cs,ssi) , h , (ip+1) )

                                | (Thread(id1,s1,e1,c3,d1)::w,st)  ->   Machine( id1 , s1 , e1 , c3 , d1 , (w,(append st [(signal,Thread(id,s,e,Present(signal,c1,c2)::c,d))])) , (cs,ssi) , h , ip )

                  else Machine( id , s , e , Throw 8::c , d , tl , (cs,ssi) , h , ip )


          (* Émission d'un signal *)
        | Machine(id,s,e,Emit signal::c,d,tl,(cs,ssi),h,ip)                         
          ->    begin 
                  try   let new_tl = reaction signal tl in Machine( id , Unit::s , e , c , d , new_tl , ((emit_signal cs id signal),ssi) , h , ip)
                  with  SignalNotInit  ->   Machine( id , s , e , Throw 8::c , d , tl , (cs,ssi) , h , ip ) 
                end


          (* Récupération dans la file d'attente *)                         
        | Machine(id,s,e,[],Vide_D,(Thread(id1,s1,e1,c,d)::w,st),si,h,ip)     ->   Machine( id1 , s1 , e1 , c , d , (w,st) , si , h , ip )


          (* Fin d'un instant logique ou fin de fonctionnement *)
        | Machine(id,s,e,[],Vide_D,([],st),si,h,ip)                           
          ->    begin
                  match st with
                      []          ->   Machine(id , s , [] , [] , Vide_D , ([],[]) , ([],[]) , Vide_H , ip)

                    | _           ->   Machine( id , s , e , [] , Vide_D , (end_of_the_moment_thread ([],st)) , (end_of_the_moment_signals si) , h , ip )
                end


          (* Je ne connais pas cette état ... *)
        | _                                                                       ->   raise StrangeEnd
  

    (* Applique les règles de la machine SECD concurrente version 3 en affichant les étapes *)
    let rec machine etat afficher= 
      match etat with
          Machine(id,Stack_const b::s,e,[],Vide_D,([],[]),si,h,ip)                ->   [Constant b]
        
        | Machine(id,Closure([Pair(abs,c)],e1)::s,e,[],Vide_D,([],[]),si,h,ip)    ->   [Pair(abs,c)]

        | Machine(id,Stack_error erreur::s,e,[],Vide_D,([],[]),si,h,ip)           ->   [Error erreur]

        | Machine(id,[],e,[Throw erreur],Vide_D,([],[]),si,h,ip)                  ->   [Throw erreur]

        | indetermine                                                             ->   if (afficher) then (afficherSECDCv3 indetermine) else printf ""; machine (transition indetermine) afficher

        
    (* Lance et affiche le résultat de l'expression *)
    let lancerSECDCv3 expression afficher = printf "Le résultat est %s \n" (string_of_control_string (machine (Machine(0,[],[],(secdLanguage_of_exprISWIM expression),Vide_D,([],[]),([],[]),Vide_H,1)) afficher ))
    
  end