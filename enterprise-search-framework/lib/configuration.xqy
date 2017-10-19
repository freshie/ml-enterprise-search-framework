xquery version "1.0-ml";

module namespace config = "https://github.com/freshie/ml-enterprise-search-framework/lib/configuration";

declare variable $BaseURI := "/enterprise-search-framework/";

declare variable $SaveQueryPermissions :=
  <permissions>
  {
    xdmp:permission("enterprise-search-framework_save-query","update"),
    xdmp:permission("enterprise-search-framework-save-query","read")
  }
  </permissions>

