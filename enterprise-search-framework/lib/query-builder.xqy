xquery version "1.0-ml";

module namespace qbl = "https://github.com/freshie/ml-enterprise-search-framework/lib/query-builder";

import module namespace pqa= "https://github.com/freshie/ml-enterprise-search-framework/pre-query-analysis-lib" at "/ext/enterprise-search-framework/lib/pre-query-analysis.xqy";
import module namespace cmq = "https://github.com/freshie/ml-enterprise-search-framework/plugins/custom-matching-query" at "/ext/enterprise-search-framework/plugins/custom-matching-query.xqy";
import module namespace cbq = "https://github.com/freshie/ml-enterprise-search-framework/plugins/custom-matching-query" at "/ext/enterprise-search-framework/plugins/custom-boosting-query.xqy";

declare function qbl:build-search-query(
  $params as map:map,
  $queryMap as map:map
)  as item()* {

  let $weightsConfigurations := map:get($params, "weightsConfigurations")

  let $qtext := map:get($params, "q")
  let $words := cts:tokenize($qtext)[. instance of cts:word]
  
  let $_ := pqa:set-query-categories($qtext, $weightsConfigurations, $queryMap)

  let $matching-query := 
    cts:and-query((
      cts:or-query((
        pqa:get-matching-query-actions($qtext, $weightsConfigurations, $queryMap),
        cmq:get($params, $queryMap),
        qbl:remove-queries-with-only-punctuations(cts:query(map:get($queryMap, "annotated-query")))
      )),
      cts:query(map:get($queryMap, "options")/additional-query/element()),
      qbl:query-for-excludes($params)
    ))
  let $boosting-query :=
     cts:or-query((
      pqa:get-boosting-query-actions($qtext, $weightsConfigurations, $queryMap),
      qbl:query-for-proximity($words, $weightsConfigurations),
      qbl:query-for-phrases(map:get($params, "phrases"), $weightsConfigurations, $words),
      qbl:query-for-elements($words, $weightsConfigurations),
      qbl:query-for-fields($words, $weightsConfigurations),
      qbl:query-for-additional-score($weightsConfigurations),
      qbl:query-for-docsize-relevancy($weightsConfigurations),
      qbl:query-for-recency($weightsConfigurations),
      qbl:query-for-date-recency($weightsConfigurations),
      cbq:get($params, $queryMap)
    )) 
  return 
    (
      $matching-query,
      $boosting-query
    )
};

declare function qbl:query-for-excludes(
  $params as map:map
) as cts:query {
  let $excludeOverrides := map:get($params, "excludeOverrides")
  return
    cts:not-query(
      cts:or-query((
        for $exclude in map:get($params, 'excludesConfiguration')/exclude
        where fn:not($excludeOverrides eq $exclude/id/text())
        return
          cts:query($exclude/query/element())
      ))
    )
};

declare function qbl:query-for-proximity(
  $words as xs:string*,
  $configurationsIn as element()*
) as cts:query* { 
  let $configurations := $configurationsIn/proximity
  let $length := fn:count($words)
  where $length gt 1
  return 
  ( 
    (: order matters :)
    if ($configurations/proximity/ordered/@useThisWeighting eq "no") then (

    ) else (
      cts:near-query(
        (
          for $word in $words
          return cts:word-query($word, ("case-insensitive","stemmed","punctuation-insensitive"), xs:double($configurations/ordered/@term))
        ),
        xs:double(xdmp:value($configurations/ordered/@distanceLength)),
        "ordered",
        xs:double($configurations/ordered/@distanceWeight)
      )
    ),
    (: order doesnt matter :)
     if ($configurations/proximity/unordered/@useThisWeighting eq "no") then (

    ) else (
      cts:near-query(
        (
          for $word in $words
          return cts:word-query($word, ("case-insensitive","stemmed","punctuation-insensitive"), xs:double($configurations/unordered/@term))
        ),
        xs:double(xdmp:value($configurations/unordered/@distanceLength)),
        "unordered",
        xs:double($configurations/unordered/@distanceWeight)
      )
    )
  )
};

declare function qbl:query-for-phrases(
  $phrasesMap as map:map,
  $configurations as element()*,
  $words as xs:string*
) as cts:query* {
  if (fn:empty($words) or $configurations/phrases/@useThisWeighting eq "no") then (
    
  ) else (
    for $vocabularyName in map:keys($phrasesMap)
    let $vocabulary := map:get($phrasesMap, $vocabularyName)
    let $terms := map:keys($vocabulary)
    for $term in $terms
    let $termTokenize:= fn:tokenize($term, ":")
    let $weight := $configurations/phrases/vocabulary[name eq $vocabularyName]/term[@nsPrefix eq $termTokenize[1] and @qname eq $termTokenize[2]]/@weight
    for $phrase in map:get($vocabulary, $term)
    return 
      cts:word-query($phrase,("case-insensitive","stemmed","punctuation-insensitive"), $weight)
  )
};

declare function qbl:query-for-elements(
  $words as xs:string*,
  $configurations as element()*
) as cts:query* {
  if (fn:empty($words) or $configurations/elements/@useThisWeighting eq "no") then (
    
  ) else (
    let $section := $configurations/elements
    let $defaultOptions := fn:tokenize($section/@defaultOptions, ", ")
    for $element in $section/element
    let $element-name := $element/@nsPrefix || ":" || $element/@name
    let $entityType := fn:tokenize($element/@entityType, "[,]+") (: handle comma or comma+space :)
    let $elementOptions := $element/@options
    let $searchOptions := 
      if (fn:exists($elementOptions)) then (
        fn:tokenize($elementOptions, ", ")
      ) else (
        $defaultOptions
      )
    return
      cts:and-query((
          cts:field-range-query("entityType", "=", ($entityType)),
          cts:element-word-query(
            xs:QName($element-name), 
            $words,
            $searchOptions,
            $element/@weight
          )
      ))
  )
};

declare function qbl:query-for-fields(
  $words as xs:string*,
  $configurations as element()*
) as cts:query* {
  if (fn:empty($words) or $configurations/fields/useServerWeights/text() eq "no") then (
    
  ) else (
    for $field in $configurations/fields/field
    return
      cts:field-word-query(
        $field,
        $words,
        (
          "case-insensitive",
          "punctuation-insensitive"
        )
      )
  )
};

(:
Function name - query-for-additional-score
This function will read the "additionalscore" from the weights.xml file and apply the options to the search query
:)
declare function qbl:query-for-additional-score(
  $configurations as element()*
) as cts:query* {
  if ($configurations/additionalscore/@useThisWeighting eq "no") then (

  ) else (
    cts:query($configurations/additionalscore/node())
  )
};

(: Builds the relevancy query for docSize.  Performs a weighted range query against
  the docSize.  The dataset and weight
  are defined in the docsizerelevancy section of weighting.xml file. :)
declare function qbl:query-for-docsize-relevancy(
  $configurations as element()*
) as cts:query* {
  if ($configurations/docsizerelevancy/@useThisWeighting eq "no") then (

  ) else (
    for $entityType in $configurations/docsizerelevancy/entityType
      return
      cts:and-query ((
          cts:field-range-query("entityType", "=", xs:string($entityType/name)),
          cts:element-range-query(
              fn:QName($entityType/fieldnamespace, "size"), ">", xs:int($entityType/maxvalue),
              (),
              $entityType/weight
          )
    ))
  )
};

(: This routine builds the recency query against the entityType defined in recency section of
    weighting.xml.  It uses the element-range-query with
    slope-factor and weighting which are both configuration items in the weighting.xml file. :)
declare function qbl:query-for-recency(
  $configurations as element()*
) as cts:query* {
  if ($configurations/recency/@useThisWeighting eq "no") then (

  ) else (

    for $item in $configurations/recency/dataset

    let $slopefactor := 
      if ($item/slopefactor) then (
        "slope-factor=" || $item/slopefactor
      ) else ( 
        "slope-factor=1"
      )
    return
      cts:and-query ((
          cts:field-range-query("entityType", "=", xs:string($item/name)),
          cts:element-range-query(
                  fn:QName($item/fieldnamespace, $item/datefield), "<", fn:current-dateTime(),
                  ("score-function=reciprocal", $slopefactor),
                  $item/weight
          )
      ))
  )
};

declare function qbl:query-for-date-recency(
  $configurations as element()*
) as cts:query {
  cts:or-query ((
    for $item in $configurations/daterecency/entityType
        let $numDays := $item/numdays
        let $operator := $item/operator
        return
        cts:and-query ((
            cts:field-range-query("entityType", "=", xs:string($item/name)),
            cts:element-range-query(
                fn:QName($item/fieldnamespace, $item/datefield), $operator, xs:dateTime(fn:current-dateTime() - xs:dayTimeDuration("P"|| $numDays ||"D")),
                ("score-function=linear"),$item/weight
            )
        ))
  ))
};