(:
 supprimer tous les textes
:)

import module namespace gp = "http:/gallicapix.bnf.fr/" at "../webapp/utils.xqm";

declare namespace functx = "http://www.functx.com";
(: declare option output:method 'html';
 
 Arguments avec valeurs par defaut 
   Args and default values               :)
   
declare variable $corpus as xs:string external   ;
declare variable $id as xs:string external    ; (: document ID :)
declare variable $idIll as xs:string external    ; (: illustration ID :)
declare variable $source as xs:string external;

declare %updating function local:delContent($ci as element()) { 

     try {
       update:output("<?xml version=""1.0"" encoding=""UTF-8""?><?xml-stylesheet href=""/static/common.css"" type=""text/css""?>
       <message>      
       <p>Texte supprime</p></message>"),  
      delete node $ci
      } catch * {
        update:output('Erreur [' || $err:code || ']: ' || $err:description)
      }           
};

try{
let $url := $corpus  
return 
if (not(gp:isAlphaNum($corpus))) then (
  (: do nothing :)
  update:output(concat("<?xml version=""1.0"" encoding=""UTF-8""?><?xml-stylesheet href=""/static/common.css"" type=""text/css""?>
       <message> Erreur corpus [ ", $corpus," ]</message>"))
) else (
 for $txt in collection($corpus)//analyseAlto[(metad/ID=$id)]//ill[@n=$idIll]//contenuText 
 return local:delContent($txt)
)}
 catch * {  
        update:output(concat("<?xml version=""1.0"" encoding=""UTF-8""?><?xml-stylesheet href=""/static/common.css"" type=""text/css""?>
       <message> Erreur exécution [ ", $err:code, " ]</message>"))
   }
