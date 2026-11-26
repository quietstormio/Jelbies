#!/bin/zsh
# usage: run.sh <name> <dd> [VAR=val ...]   (env vars passed to the UI test as TEST_RUNNER_)
S=/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/show-soak-r1
NAME=$1; DD=$2; shift 2
UDID=$(cat $S/udid.txt)
OUT=$S/runs/$NAME; mkdir -p $OUT
for kv in "$@"; do export TEST_RUNNER_${kv}; done
export TEST_RUNNER_SOAK_OUT=$OUT
xcodebuild test-without-building -parallel-testing-enabled NO -xctestrun $(ls $DD/Build/Products/*.xctestrun | head -1) -destination "id=$UDID" -only-testing:BobV1UITests/ShowSoakUITests/testSoak -resultBundlePath $OUT/result.xcresult > $OUT/xcodebuild.log 2>&1
echo "exit $?" >> $OUT/xcodebuild.log
