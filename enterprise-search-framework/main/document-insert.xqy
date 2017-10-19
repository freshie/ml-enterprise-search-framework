xquery version "1.0-ml";

declare namespace sec = "http://marklogic.com/xdmp/security";

declare variable $URI as xs:string external;
declare variable $DOC external;
declare variable $COLLECTIONS as element(collections) external;
declare variable $PERMISSIONS as element(permissions) external;
declare variable $QUALITY as xs:int external;

xdmp:document-insert(
  $URI, 
  $DOC, 
  $PERMISSIONS/sec:permission, 
  $COLLECTIONS/collection/text(),
  $QUALITY
)