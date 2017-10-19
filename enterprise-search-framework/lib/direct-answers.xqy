xquery version "1.0-ml";

module namespace ad = "https://github.com/freshie/ml-enterprise-search-framework/lib/direct-answers";

import module namespace config = "https://github.com/freshie/ml-enterprise-search-framework/lib/configuration" at "/ext/enterprise-search-framework/lib/configuration.xqy";

declare namespace sparql = "http://www.w3.org/2005/sparql-results#";
declare namespace skos="http://www.w3.org/2004/02/skos/core#";
declare namespace rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";

declare function ad:get(
 $params as map:map,
 $queryMap as map:map
) as map:map {
  let $qtext := map:get($params, "q")
  let $qtext := fn:lower-case($qtext)
  return
    if (fn:normalize-space($qtext) eq "") then (

    ) else (
      let $searchOptions := ("diacritic-sensitive","punctuation-sensitive","whitespace-sensitive","unstemmed","unwildcarded")
      let $elementsToSearch :=  (xs:QName("skos:altLabel"), xs:QName("skos:prefLabel"))
      let $phrase := rdf:langString($qtext, "en")
      let $collection-query := cts:collection-query($config:BaseURI || "direct-answers")
      let $phrase-words := fn:tokenize(fn:normalize-space($qtext), " ")
      let $word-queries :=
        if (fn:count($phrase-words) = 1) then
          cts:element-value-query($elementsToSearch, $phrase-words, $searchOptions)
        else
          let $queries :=
            cts:and-query((
              for $word in $phrase-words
              return
                cts:element-word-query($elementsToSearch, $word, $searchOptions)
           ))
          let $maps :=
            for $word in $phrase-words
            return
              cts:element-value-match(
                $elementsToSearch,
                fn:concat("*", $word, "*"),
                (
                  "case-insensitive",
                  "diacritic-insensitive",
                  "map"
                ),
                $queries
              )
          let $values := 
            map:keys(
              fn:fold-left(
                function($acc, $value) { $acc * $value }, 
                $maps[1], 
                $maps
              )
            )
          return
              cts:element-word-query($elementsToSearch), $values, $searchOptions)

      return
        cts:search(
          fn:doc(), 
          cts:and-query(($collection-query, $word-queries))
        )[1]
    )
};

declare function ad:format-results(
 $results as map:map,
 $queryMap as map:map,
 $params as map:map
) as map:map {
  json:object(
    <json:object>
      <json:entry>
        <json:key>answers</json:key>
          <json:value>
            {
              let $array := json:array()
              let $items := map:get($results, "direct-answers")
              let $_ := json:array-push($array, $items)
              return $array
            }
          </json:value>
        </json:entry>
    </json:object>
  )
};

(:

 if (fn:exists($description)) then
                 <json:object>
                    <json:entry>
                      <json:key>title</json:key>
                      <json:value>{$description/skos:prefLabel/text()}</json:value>
                    </json:entry>
                    <json:entry>
                      <json:key>description</json:key>
                      {
                          if ($description/orderdefinition:definition1/text()) then
                              <json:value>{$description/orderdefinition:definition1/text()}</json:value> 
                          else (),
                          if ($description/orderdefinition:definition2/text()) then
                              <json:value>{$description/orderdefinition:definition2/text()}</json:value>
                          else (),
                          if ($description/orderdefinition:definition3/text()) then
                              <json:value>{$description/orderdefinition:definition3/text()}</json:value>
                          else (),
                          if ($description/orderdefinition:definition4/text()) then
                              <json:value>{$description/orderdefinition:definition4/text()}</json:value>
                          else (),
                          if ($description/orderdefinition:definition5/text()) then
                              <json:value>{$description/orderdefinition:definition5/text()}</json:value>
                          else (),
                          if ($description/orderdefinition:definition6/text()) then
                              <json:value>{$description/orderdefinition:definition6/text()}</json:value>
                          else (),
                          if ($description/orderdefinition:definition7/text()) then
                              <json:value>{$description/orderdefinition:definition7/text()}</json:value>
                          else ()
                      } 
                    </json:entry>
                 </json:object>
             else 
                 ()
:)