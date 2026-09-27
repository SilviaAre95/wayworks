# The shape every marketplace.json must have, checked on the JSON itself.
# Prints one line per violation; no output means the shape holds.
#
# An allowlist, evaluated before anything splits names into lines: a name
# holding a newline (or any character outside [a-z0-9-]) would otherwise read
# as several existing plugins and hide a new entry from every later check.
# Values are echoed with tojson so no violation message can split either.
# Used by check-manifests.sh and check-release-rule.sh.
# \A and \z, not ^ and $: in jq's regex, $ also matches before a final newline.
def semver: type == "string" and test("\\A(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\z");
def plugin_name: type == "string" and test("\\A[a-z0-9][a-z0-9-]*\\z");

if (.plugins | type) != "array" then "marketplace.json has no plugins array"
else
  (.plugins[] |
    if (.name | plugin_name | not) then "plugin name \(.name | tojson) is not a [a-z0-9-] string"
    elif .source != "./plugins/\(.name)" then "\(.name): source \(.source | tojson) is not \"./plugins/\(.name)\""
    elif (.version | semver | not) then "\(.name): version \(.version | tojson) is not X.Y.Z"
    else empty end),
  (.plugins | map(.name | tojson) | group_by(.) | map(select(length > 1) | .[0]) | .[]
    | "plugin name \(.) is listed more than once"),
  (if (.metadata.version | semver | not) then "metadata.version \(.metadata.version | tojson) is not X.Y.Z" else empty end)
end
