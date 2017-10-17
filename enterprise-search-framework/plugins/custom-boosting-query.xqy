xquery version "1.0-ml";

module namespace lib = "https://github.com/freshie/ml-enterprise-search-framework/plugins/custom-boosting-query";

declare function lib:get(
  $params as map:map, 
  $queryMap as map:map
) as cts:query* {
  ()
  (: 
    example code below

    lib:query-for-project-recency(map:get($params, "weightsConfigurations"))
  :)
};

(:
  This is commented out because you its meant to be an example of what could be done
  The range indexes would also have to be put on these elements 

(: Builds the recency query for projects.  Performs a weighted slope range query against
  the Approved Date and a weighted query against the project status.  The fields, slope and weight
  are defined in the projectrecency section of weighting.xml file.  :)
declare function lib:query-for-project-recency(
        $configurations as element()*
) as cts:query* {
   if ($configurations/projectrecency/@useThisWeighting eq "no") then (

   ) else (
    cts:and-query ((
        let $project := $configurations/projectrecency
        let $slopefactor := "slope-factor=" || $project/slopefactor
        return
            cts:element-range-query(
                    fn:QName($project/fieldnamespace, $project/datefield), "<", fn:current-date(),
                    ("score-function=reciprocal", $slopefactor),
                    $project/weight
            ),
        (: build the project status weight queries :)
        cts:or-query ((
            for $status in $configurations/projectrecency/projectstatus/value
            let $weight := $status/@weight
            return
                cts:element-value-query(xs:QName("projectStatus"), $status/text(), (), $weight)
        ))
    ))
  )
}; :)