xquery version "1.0-ml";

module namespace utilities = "https://github.com/freshie/ml-enterprise-search-framework/lib/utilities";

declare function utilities:get-node-size(
  $doc as document-node()
) as xs:unsignedLong {
  xdmp:binary-size(xdmp:unquote(xdmp:quote($doc),(),"format-binary")/binary())
};

declare function utilities:get-permutations(
  $items as xs:string*
) as xs:string* {
  if (fn:count($items) le 1) then
    $items
  else
    for $i in 1 to fn:count($items)
    return
      for $perm in utilities:get-permutations(fn:remove($items, $i))
      return
        fn:string-join(fn:insert-before($perm, 1, $items[$i]), " ")
};

(:
  Takes in a string and a squance of words.
  Removes the words from the string.
:)
declare function utilities:remove-words-from-string(
  $stringIN as xs:string?,
  $wordsIN as xs:string*
) as xs:string* {
  if (fn:empty($wordsIN) or fn:empty($stringIN)) then (
    $stringIN
  ) else (
    let $string := fn:lower-case($stringIN)
    let $wordsJoined := fn:string-join($wordsIN, "\b|")
    let $wordsJoined := "\b"|| $wordsJoined 
    return
    (:
       need to use javascript because xquery doesnt have forward lookups
       Its also much faster in javascript
    :)
     xdmp:javascript-eval(
       " 
         var text; 
         var match;
         re = new RegExp(match, 'g');
         text.replace(re, ' ')",
       (
         "text",$string,
         "match",$wordsJoined
        )
     )
   )
};