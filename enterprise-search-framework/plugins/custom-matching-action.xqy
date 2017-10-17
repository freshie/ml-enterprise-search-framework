xquery version "1.0-ml";

module namespace lib = "https://github.com/freshie/ml-enterprise-search-framework/plugins/custom-matching-action";


declare function lib:get(
	$queryMap as map:map, 
	$queryText as xs:string,
  $configurations as element(),
  $uri as xs:string
) as cts:query* {
	()
	(: 
		example code below

		
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
        cts:and-query((
          (
            $termsFromOtherParts ! cts:word-query(.)
          ),
          $nonMatchingTerm ! cts:word-query(., $WordQueryOptions, $weight)
        ))     
	:)
};
