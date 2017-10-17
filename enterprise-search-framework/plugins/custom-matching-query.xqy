xquery version "1.0-ml";

module namespace lib = "https://github.com/freshie/ml-enterprise-search-framework/plugins/custom-matching-query";

(: import module namespace util = "https://github.com/freshie/ml-enterprise-search-framework/utilities-lib" at "/ext/enterprise-search-framework/lib/utilities.xqy"; :)

declare function lib:get(
	$params as map:map, 
	$queryMap as map:map
) as cts:query* {
	()
	(: 
		example code below

		let $weightsConfigurations := map:get($params, "weightsConfigurations")

		let $qtext := map:get($params, "q")
		let $words := cts:tokenize($qtext)[. instance of cts:word]
		return
		(
			lib:query-for-people($qtext, $weightsConfigurations, $words),
			lib:query-for-phone-numbers($qtext, $weightsConfigurations)
		)
	:)
};

(:
	This is commented out because you its meant to be an example of what could be done
	The range indexes would also have to be put on these elements 

declare function lib:query-for-people(
  $qtext as xs:string,
  $configurations as element()*,
  $ctsWords as xs:string*
) as cts:query* {
  if (fn:empty($ctsWords) or fn:string-length($qtext) le 2 or $configurations/partialMatch/personName/@useThisWeighting eq "no") then (
  
  ) else ( 
    let $partial := fn:replace($qtext,'"','')
    let $partial := if (fn:string-length($partial) le xs:int(2)) then () else fn:normalize-space($partial)
    let $partial := if (fn:contains($partial,":")) then () else $partial

    let $wordCount := fn:count($ctsWords)
    where $wordCount le 5 and $wordCount ge 1
    return 
      let $permutations := util:getPermutations($ctsWords)

      let $element := xs:QName("fullName")

      let $query :=  cts:collection-query("people")

      let $personNameConfigurations := $configurations/partialMatch/personName
      let $slopeFactor := ($personNameConfigurations/@slopeFactor, "1.0")[1] 
      let $weight := (xs:double($personNameConfigurations/@weight), 16.0)[1]
      let $scoreFunction := ($personNameConfigurations/@scoreFunction, "linear")[1]
      
      let $values :=
        for $permutation at $index in json:array-values($permutations)
        let $words := json:array-values($permutation)

        let $first-match := fn:string-join($words, " ") || "*"
        let $match := "* " || fn:string-join($words, "* ") || "*"    
        let $match2 := fn:string-join($words, "* ") || "*"
        let $options := 
          (
            "eager",
            "concurrent",
            "case-insensitive",
            "diacritic-insensitive"
          )
        return
        (
          if ($index eq 1) then 
            cts:element-value-match(
              $element, 
              $first-match, 
              $options, 
              $query
            )
          else (),
          cts:element-value-match(
            $element,
            $match,
            $options,
            $query
          ),
          cts:element-value-match(
            $element, 
            $match2, 
            $options, 
            $query
          )
        )
      where fn:exists($values)
      return
        cts:element-range-query(
          $element, 
          "=", 
          $values, 
          (
            "score-function=" || $scoreFunction, 
            "slope-factor=" || $slopeFactor
          ), 
          $weight
        )
  )
};

declare function lib:query-for-phone-numbers(
  $qtext as xs:string,
  $configurations as element()
) as cts:query* {
  if (fn:empty($qtext) or $qtext eq "" or $configurations/partialMatch/phoneNumbers/@useThisWeighting eq "no" or fn:empty($configurations/phoneNumbers) or fn:empty(fn:analyze-string($qtext,"[0-9]")/s:match)) then (

  ) else (
    (: 
        removed normal phone number addon texts
        such as () - x and spaces  
     :)
    let $queryText := fn:replace($qtext, "[()-/x\W]", "")
    let $weight := (xs:double($configurations/partialMatch/phoneNumbers/@weight), 64.0)[1]
    where $queryText ne ""
    return
      cts:element-attribute-value-query(
        (
          xs:QName("telephone"), 
          xs:QName("mobile"),
          xs:QName("workPhone")
        ),
        (
          xs:QName('extension'), 
          xs:QName('local'), 
          xs:QName('numeric') 
        ), 
        $queryText,
        "exact",
        $weight
      )
  )
};

:)