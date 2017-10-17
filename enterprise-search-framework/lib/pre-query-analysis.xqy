xquery version "1.0-ml";

module namespace pqa = "https://github.com/freshie/ml-enterprise-search-framework/lib/pre-query-analysis";

import module namespace config = "https://github.com/freshie/ml-enterprise-search-framework/lib/configuration" at "/ext/enterprise-search-framework/lib/configuration.xqy";
import module namespace cma = "https://github.com/freshie/ml-enterprise-search-framework/plugins/custom-matching-query" at "/ext/enterprise-search-framework/plugins/custom-matching-action.xqy";

declare variable $WordQueryOptions := ("unstemmed", "case-insensitive", "diacritic-insensitive", "punctuation-insensitive", "whitespace-insensitive");

declare function pqa:setQueryCategories(
  $queryText as xs:string,
  $configurations as element()*,
  $queryMap as map:map
) as item()* {
  if (fn:empty($queryText) or $queryText eq "" or $configurations/queryCategoriesActions/@useThisWeighting eq "no" or fn:empty($configurations/queryCategoriesActions)) then (

  ) else (
    let $node := <x>{$queryText}</x>
    let $uris := 
     cts:uris(
        (),
        ("concurrent"),  
        cts:and-query((
          cts:collection-query($config:BaseURI || "queryCategories-recognize"),
          cts:reverse-query($node)
        ))
      )
    let $types :=
      for $uri in $uris
      return 
        fn:substring-before($uri, ".xml") ! fn:substring-after(., $config:BaseURI || "queryCategories/")

    let $types := fn:distinct-values($types)
    let $_ := 
      (
        map:put($queryMap, "queryCategories", $types),
        map:put($queryMap, "queryCategoriesURIS", $uris)
      )

    return $types 
  )
};


declare function pqa:getBoostingQueryActions(
  $queryText as xs:string,
  $configurations as element()*,
  $queryMap as map:map
) as cts:query* {
  if (fn:empty($queryText) or $queryText eq "" or $configurations/queryCategoriesActions/@useThisWeighting eq "no" or fn:empty($configurations/queryCategoriesActions)) then (

  ) else (

    for $type in map:get($queryMap, "queryCategories")
    let $actionNode := $configurations/queryCategoriesActions/action[@type = $type]/boostingQuery
    where fn:exists($actionNode)
    return   
      cts:query($actionNode/element())
  )
};

declare function pqa:getMatchingQueryActions(
  $queryText as xs:string,
  $configurations as element()*,
  $queryMap as map:map
) as cts:query* {
  if (map:get($queryMap,"query-has-grammar") eq fn:true() or fn:empty($queryText) or $queryText eq "" or $configurations/queryCategoriesActions/@useThisWeighting eq "no" or fn:empty($configurations/queryCategoriesActions)) then (

  ) else (

    for $uri in map:get($queryMap, "queryCategoriesURIS")
    let $doc := fn:doc($uri)
    let $type := $doc/queryCategory/queryType/text()
 
    let $actionNode := $configurations/queryCategoriesActions/action[@type = $type]/matchingQuery

    (: this gets all the terms that were in the document(s) that matched :)
    let $terms :=
      cts:walk(
        $doc, 
        cts:word-query($queryText, $WordQueryOptions), 
        $cts:node/../../../cts:word-query/cts:text/text()
      )
   
    let $terms := fn:distinct-values($terms)

    where fn:exists($terms) and fn:exists($actionNode)
    return
      for $element in $actionNode/element()
      let $weight := 
        (
          $element/@weight, 
          0
        )[1]

      let $termsToQuery := 
        cts:or-query((
          $terms ! cts:word-query(., $WordQueryOptions, $weight)
        ))

      let $otherParts := 
        cts:highlight(<x>{$queryText}</x>, $termsToQuery, "")/node()

      let $termsFromOtherParts := 
        fn:tokenize(fn:normalize-space($otherParts), " ") 

      let $matchingTerm :=
      cts:walk(<x>{$queryText}</x>, $termsToQuery, $cts:text)

      let $nonMatchingTerm :=
        fn:remove($terms, fn:index-of($terms, $matchingTerm))

      where fn:exists($nonMatchingTerm) and $nonMatchingTerm ne ""
      return 
        switch (fn:local-name($element))
          case "element-value-query" return
            let $addToMap := pqa:addToExpansions($type, "element-value of " || xs:QName($element/text()), $nonMatchingTerm, $queryMap)
            return
              cts:and-query((
                $termsFromOtherParts ! cts:word-query(.),
                cts:element-value-query(xs:QName($element/text()), $nonMatchingTerm, "exact",  $weight)
              ))
          case "word-query" return 
            let $addToMap :=  pqa:addToExpansions($type, "word-query", $nonMatchingTerm, $queryMap)
            return 
              cts:and-query((
                (
                  $termsFromOtherParts ! cts:word-query(.)
                ),
                $nonMatchingTerm ! cts:word-query(., $WordQueryOptions, $weight)
              ))     
          default return 
            cma:get($queryMap, $queryText, $configurations, $uri)         
  )
};