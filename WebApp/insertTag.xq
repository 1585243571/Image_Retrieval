(:
 insérer un tag sémantique dans une illustration
:)


declare namespace functx = "http://www.functx.com";
(: declare option output:method 'html';
 
 Arguments avec valeurs par defaut 
   Args and default values               :)
   
declare variable $corpus as xs:string external    ;
declare variable $id as xs:string external   ;
declare variable $n as xs:string external   ;  (: illustration number :)
declare variable $tag as xs:string external   ; (: semantic tag :)
declare variable $source as xs:string external   ;


declare %updating function local:replaceIll($ill as element()) { 
   
    if (($tag != ""))  then (
       try {
      update:output(concat ("<?xml version=""1.0"" encoding=""UTF-8""?><?xml-stylesheet href=""/static/common.css"" type=""text/css""?>
       <message>      
       <p>Concept signalé dans l'illustration : <b>",$tag,"</b></p></message>")),
      insert node (if ($ill/@edit) then () else (attribute edit { "1" })) into $ill, (: ajout d'un attribut edit :) 
      if  (matches($tag,"color")) then (
         insert node <contenuImg source='{data($source)}' CS='1' lang='en' coul='1' time="{fn:current-dateTime()}">{data($tag)}</contenuImg> into $ill)
        else (
      insert node <contenuImg source='{data($source)}' CS='1' lang='en' time="{fn:current-dateTime()}">{data($tag)}</contenuImg> into $ill)
      } catch * {
        update:output('Erreur [' || $err:code || ']: ' || $err:description)
      }
    
    )           
   else (update:output("<?xml version=""1.0"" encoding=""UTF-8""?><?xml-stylesheet href=""/static/common.css"" type=""text/css""?>
       <message><p>Aucune mise à jour</p></message>"))
      
};

(:declare %updating function local:replaceCouleur($ill as element()) {
  if (($color != "undef") and ($ill/@couleur != $color)) then (
  db:output("Update successful."), replace value of node $ill/@couleur with $color
  )
  else ()
}; 
:)

let $res := "foo"  
return 

local:replaceIll(collection($corpus)//analyseAlto[(metad/ID =$id)]//ill[@n=$n]) 

