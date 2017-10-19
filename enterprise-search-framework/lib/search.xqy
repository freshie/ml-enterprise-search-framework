xquery version "1.0-ml";

module namespace searchlib = "https://github.com/freshie/ml-enterprise-search-framework/lib/search";

import module namespace qbl = "https://github.com/freshie/ml-enterprise-search-framework/lib/query-builder" at "/ext/enterprise-search-framework/lib/query-builder.xqy";
import module namespace util = "https://github.com/freshie/ml-enterprise-search-framework/lib/utilities" at "/ext/enterprise-search-framework/lib/utilities.xqy";
import module namespace config = "https://github.com/freshie/ml-enterprise-search-framework/lib/configuration" at "/ext/enterprise-search-framework/lib/configuration.xqy";
import module namespace savedQuery = "https://github.com/freshie/ml-enterprise-search-framework/lib/saved-query" at "/ext/enterprise-search-framework/lib/saved-query.xqy";
import module namespace answers = "https://github.com/freshie/ml-enterprise-search-framework/lib/direct-answers" at "/ext/enterprise-search-framework/lib/direct-answers.xqy";
import module namespace spell-correct = "https://github.com/freshie/ml-enterprise-search-framework/lib/spell-correct" at "/ext/enterprise-search-framework/lib/spell-corrections.xqy";
import module namespace related-search = "https://github.com/freshie/ml-enterprise-search-framework/lib/related-search" at "/ext/enterprise-search-framework/lib/related-search.xqy";

declare function searchlib:get-results(
  $params as map:map,
  $queryMap  as map:map,
  $searchOptions as xs:string*,
  $andQuery as cts:query
) as document-node()* {

  let $start := (map:get($params, "start"), 1)[1]
  let $end := $start + (map:get($params, "pageLength"), 0)[1]

  let $query :=
    cts:boost-query(
      cts:and-query((
        map:get($queryMap, "matching-query")
        $andQuery
        )),
      map:get($queryMap, "boost-query")
    )
  return 
    cts:search(fn:doc(), $query, $searchOptions)[$start to $end]

};

declare function searchlib:post_implementation(
  $context as map:map,
  $params as map:map,
  $input as document-node()
) as document-node()? {
  let $newParams := searchlib:build-parmas-from-body($params, $input)
  return 
    searchlib:get_implementation($context, $newParams) 
};

declare function searchlib:build-parmas-from-body(
  $params as map:map,
  $input as document-node()
) as map:map* {
  let $jsonParmas := map:map()
  let $string := xdmp:quote($input)

  let $json := xdmp:unquote($string)
  let $_:= $json/node()/node() ! map:put($jsonParmas, xs:string(fn:node-name(.)), .) 
  return 
    map:new(($params, $jsonParmas))
};

(:
  This is the main function for searches get requests
:)
declare function searchlib:get_implementation(
  $context as map:map,
  $paramsIN as map:map
) as document-node() {
  
  (: this allows any domain to make requests to this endpoint :)
  let $addHeader := xdmp:add-response-header("Access-Control-Allow-Origin","*")

  let $spellCorrections := spell-correct:get-spell-corrections($paramsIN)
  
  let $preparedSearchItems as item()+ := searchlib:prepare-search-parameters($paramsIN)
  let $params as map:map():= $preparedSearchItems[1]
  let $queryMap as map:map() := $preparedSearchItems[2]

  (: this saves each request :)

  (: 
    TODO: create a way to get the users
  :)
  let $_ := savedQuery:add("placeHolder For Users", $queryMap, $params, 'history')


  let $results := searchlib:get-results($params, $queryMap, "unfiltered", cts:true-query())

  let $directAnswers := searchlib:add-direct-answers($params, $queryMap)

  let $results :=
    if ($format eq 'json') then (
      searchlib:format-results($results,$sourcefacetMap)
    ) else ($results)
  
  
  return
    if ($format = "json")
    then (

      let $response := xdmp:from-json($results)
      
      let $_ := map:put($response, "directAnswers", $directAnswers)

      let $_ := map:put($response, "phrases", map:get($params, "phrases"))

      let $_ := map:put($response, "queryCategories", map:get($queryMap, "queryCategories")) 

      let $_ := map:put( $response, "expansions", map:get($queryMap, "expansions") ) 

      let $_ :=
        if (map:get($params, "debug") = "true") then (
            
            (
              map:put($response, "queryMap", $queryMap),
              map:put($response, "params", $params )
            )

        ) else ()

      let $_ := map:put($response,"excludes", searchlib:format-excludes($params) )

      let $_ := map:put($response, "relatedSearches", related-search:get-related-search($params))

      let $_ := map:put($response, "spellCorrections", spell-correct:get-spell-corrections-map($spellCorrections))

      let $_ := xdmp:set-response-content-type("application/json")
     
      return document {xdmp:to-json($response) } )

    else document {$results}
};


(:
   if its the first page and the flag is set ot true 
   then it will lookup answers bast on the queryText
:)
declare function searchlib:add-direct-answers(
 $params as map:map,
 $queryMap as map:map
) as map:map {
   let $results :=
     if ((map:get($params,"start") eq 1 or fn:empty(map:get($params,"start"))) and (map:get($params,"getDirectAnswers") eq "true")) then
      answers:get($params, $queryMap)
    else
      map:map()

  return answers:format-results($results, $queryMap, $params)
  
};

(:
  Checks to make sure there is an entity document
  if not uses the default options
:)
declare function searchlib:get-options(
  $entity as xs:string
) as item()* {
  let $defaultOptions := fn:doc($config:BaseURI || "configurations/options-default.xml")/node()

  let $entityOptionsURI := $config:BaseURI || "configurations/options-"|| $entity || "default.xml"

  return 
    if (fn:doc-available($entityOptionsURI)) then (
      fn:doc($entityOptionsURI)/node()
    ) else (
      $defaultOptions
    )
};

declare function searchlib:format-excludes(
  $params as map:map
) as node() {
  array-node {
    let $excludeOverrides := map:get($params, "excludeOverrides")
    for $exclude in map:get($params, 'excludesConfiguration')/exclude
    let $id := $exclude/id/text()
    let $excludeOverrides := $excludeOverrides eq $id
    return 
      map:new((
        map:entry("id", $id),
        map:entry("label", $exclude/label/text()),
        map:entry("override", $excludeOverrides)
      ))
  }
};

declare function searchlib:get-phrases(
  $qtext as xs:string,
  $configurationsIn as element()*
) as map:map* {
  if (fn:empty($qtext) or $qtext eq "" or $configurationsIn/phrases/@useThisWeighting = "no")
  then ()
  else (
    let $node := <node>{$qtext}</node>

    let $vocabularys := $configurationsIn/phrases/vocabulary

    let $phrases :=
      cts:search(
        fn:doc(),
        cts:and-query((
          cts:collection-query((
            for $name in $vocabularys/name/xs:string(.)
            return $config:BaseURI || "vocabularies/" || $name
          )),
          cts:reverse-query($node)
        )),
        ("unfiltered","score-zero")
      )

    let $phraseMap := map:new(())

    let $buildPhraseMap :=
      for $doc in $phrases
      let $type := xdmp:document-get-collections(xdmp:node-uri($doc)) ! fn:substring-after(., $config:BaseURI || "vocabularies/")[. ne ""]

      let $elements := ($doc/element()/element(), $doc/element()/element()/element())

      let $terms := $vocabularys[name eq $type]/term

      for $term in $terms
      let $termAsQNames :=
          if($term/@nsPrefix != "")then (
            $term/@nsPrefix || ":"|| $term/@qname
          )else(
            $term/@qname
          )
        (: $term/@nsPrefix || ":"|| $term/@qname :)
      let $phrase := $elements[xs:string(fn:node-name(.)) eq $termAsQNames]/xs:string(.)
      let $previousTypeValue := (map:get($phraseMap, $type), map:new(()))[1]
      let $newValue := 
        let $previousTermValue := map:get($previousTypeValue, $termAsQNames)
        let $newTermValue := fn:distinct-values(($previousTermValue, $phrase))
        let $put := map:put($previousTypeValue, $termAsQNames, $newTermValue)
        return $previousTypeValue

      let $put := map:put($phraseMap, $type, $newValue)
      return $phraseMap

    return $phraseMap
 )
};

(: 
  checsk to see if there is any grammer used in the query 
:)
declare function searchlib:check-for-grammar(
 $query as xs:string,
 $options as element()
) as xs:boolean {
  let $grammarNode := $options/grammar
  let $grammarTerms :=
    ($grammarNode//text(), $grammarNode/starter/@delimiter)

  let $checks :=
    for $grammarTerm in   $grammarTerms
    return 
      if ($grammarTerm eq ("]", "[", "(", ")") ) then (
        fn:contains($query, $grammarTerm )
      ) else (
        fn:contains($query, " " || $grammarTerm  || " " )
      )
  return  $checks eq fn:true()
};

(:
    build a map that has many attributes about the query 
:)
declare function searchlib:generate-query-map(
 $params as map:map
) as map:map {

  let $queryMap := map:map()

  let $_ := map:put($queryMap, "options", searchlib:get-options($params))


(:
  change to a better parser 

  let $annotated-query := search:parse(
          (map:get($params,"q"),"")[1],
          $options-with-facets,
          "cts:annotated-query"
  )

  let $_ := map:put($queryMap, "annotated-query", $annotated-query)
:)

  let $query-has-grammar := 
    searchlib:check-for-grammar(map:get($params,"q"), map:get($queryMap,"options"))

  let $_ := map:put($queryMap, "query-has-grammar", $query-has-grammar) 

  let $weightsConfigurations := map:get($params, "weightsConfigurations")
 
  let $buildQuery := qbl:build-search-query($params, $queryMap)
  
  let $_ := map:put($queryMap, "matching-query", $buildQuery[1])
  let $_ := map:put($queryMap, "boost-query", $buildQuery[2])

  return $queryMap
};

(:
    goes through some keys in the param map
    adds some new params to the map
:)
declare function searchlib:generate-params-map(
  $params as map:map
) as map:map {
    
    let $newMap := map:new($params)
    
    let $_ := map:put($newMap,"start", xs:integer( (map:get($params,"start"), 1)[1] )
    let $_ := map:put($newMap,"pageLength", xs:integer( (map:get($params,"pageLength"), 10)[1])

    (:
      2-letter ISO language codes 
      http://www.loc.gov/standards/iso639-2/php/code_list.php
    :)
    let $_ := map:put($newMap,"language", (map:get($params,"language"), "en")[1] )

    
    let $stopWords := 
      fn:doc($config:BaseURI || "dictionaries/" || map:get($newMap, "language") || "/stopwords.xml")/spell:dictionary/spell:word/text();
       
    let $_ := map:put($newMap, "stopWords", $stopWords)

    (:
      TODO: have a flag that checks if they want stop words removed

      removes stops words
    :)
    let $clean-q := 
      util:remove-words-from-string(
        xdmp:url-decode(map:get($params,"q")), 
        map:get($newMap, "stopWords")
      )
    
    let $boosted-q :=
        if (map:get($params, "boost")) then
            fn:concat($clean-q, ' BOOST "', map:get($params, "boost"), '"')
        else
            $clean-q
    
    let $_ := map:put($newMap, "q", $boosted-q)
    let $_ := map:put($newMap, "query-as-entered", map:get($params,"q"))
    let $_ := map:put($newMap, "returnAnswers", map:get($params,"returnAnswers"))
    let $_ := map:put($newMap, "entity", (map:get($params,"entity"), "default")[1])
    let $_ := map:put($newMap, "format", (map:get($params,"format"),"json")[1])
    let $_ := map:put($newMap, "excludeOverrides", fn:tokenize(map:get($params, "excludeOverrides"), ","))

    let $excludesConfiguration :=
    (
      cts:search(fn:doc(), 
        cts:and-query((cts:collection-query("configuration"),cts:element-query(xs:QName("excludes"), cts:true-query())))
      )
    )[1]/element()

    let $_ := map:put($newMap, "excludesConfiguration", $excludesConfiguration)

    let $weightsConfigurationsFile := (map:get($newMap,"weightFile"),"weights")[1]

    let $weightsConfigurations := fn:doc($config:BaseURI "configuration/weights-"|| $weightsConfigurationsFile || ".xml")/element()

    let $_ := map:put($newMap, "weightsConfigurations", $weightsConfigurations)

    let $phrases := searchlib:get-phrases(map:get($newMap,"q"), $weightsConfigurations)

    let $_ := map:put($newMap, "phrases", $phrases)

    return $newMap
};

declare function searchlib:prepare-search-parameters(
    $paramsIN as map:map
) as item()+ {
    let $params := searchlib:generate-params-map($paramsIN)
    let $queryMap := searchlib:generate-query-map($params)
    return 
      (
        $params, 
        $queryMap
      )
};