U=$(cat sim.txt)
for s in "$@"; do perl -e 'alarm 3000; exec @ARGV' xcodebuild test-without-building -scheme BobV1 -destination "id=$U" -derivedDataPath ./dd_i2 -only-testing:BobV1Tests/$s -parallel-testing-enabled NO > logs/$s.log 2>&1; echo "$s rc=$? $(grep -E "Executed [0-9]+ tests" logs/$s.log | tail -1)" >> logs/summary.txt; done
echo ALLDONE >> logs/summary.txt
