xquery version "1.0-ml";

module namespace saved-query-lib = "https://github.com/freshie/ml-enterprise-search-framework/lib/saved-query";

import module namespace util = "https://github.com/freshie/ml-enterprise-search-framework/lib/utilities" at "/ext/enterprise-search-framework/lib/utilities.xqy";
import module namespace config = "https://github.com/freshie/ml-enterprise-search-framework/lib/configuration" at "/ext/enterprise-search-framework/lib/configuration.xqy";


declare function saved-query-lib:add(
	$user as xs:string,
	$queryMap as map:map,
	$params as map:map,
	$status as xs:string
) as item()* {

	let $current := xs:string(fn:current-dateTime() + xdmp:elapsed-time())

	let $uri := $config:BaseURI || "saved-query/" || $user || "/" || $current || ".xml"

  let $query := map:get($queryMap,"matching-query")

  let $queryText := map:get($params,"query-as-entered")

  let $name := map:get($params,"name")
  
  (:
    if $name is empty we use query as the name
    if $name is still empty we use set a default name
  :)
  let $name :=
    ($name, $queryText, "Unnamed")[1]

  let $id := util:hashInputs(($queryMap, $params))

	let $doc :=
    <savedQuery id="{$id}">
     <name>{$name}</name>
     <user>{$user}</user>
     <status>{$status}</status>
     <query>{$query}</query>
     <queryText>{$quertText}</queryText>
     <timeSaved>{$current}</timeSaved>
    </savedQuery>

  let $collections :=
    <collections>
       <collection>{$config:BaseURI}users/{$user}</collection>
       <collection>{$config:BaseURI}saved-queries</collection>
    </collections>

  let $_ :=
    xdmp:spawn(
      "/ext/enterprise-search-framework/main/document-insert.xqy",
      (
        xs:QName("URI"), $savedQueryUri,
        xs:QName("DOC"), $doc,
        xs:QName("PERMISSIONS"), $config:SavedQueryPermissions,
        xs:QName("COLLECTIONS"), $collections,
        xs:QName("QUALITY"), 0
      )
    )
      
    return ()
};