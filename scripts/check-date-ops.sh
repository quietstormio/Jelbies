#!/bin/bash
# Usage: check-date-ops.sh <path to .app>. Fails if any Mach-O inside imports Foundation's back-deployed Date.<= / Date.>= (null on an older iOS 27.2 beta).
app="${1:?usage: check-date-ops.sh path/to/App.app}"; bad=0
while IFS= read -r f; do
  file "$f" | grep -q 'Mach-O' || continue
  if nm -u "$f" 2>/dev/null | grep -qE 'Foundation4DateV2(le|ge)oi'; then echo "BAD: $f imports Date.<= / Date.>="; bad=1; fi
done < <(find "$app" -type f \( -perm -u+x -o -name '*.dylib' \))
[ $bad = 0 ] && echo "OK: no Mach-O in $app imports Foundation's Date.<= / Date.>="
exit $bad
