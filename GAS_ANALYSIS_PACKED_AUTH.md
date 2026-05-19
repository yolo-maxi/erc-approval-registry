# Packed auth bytes gas analysis

Branch: `packed-auth-bytes-sim`
Baseline: `origin/master` at `d9338a53`

## Variant implemented

Storage changes from:

```solidity
mapping(address owner => mapping(address operator => mapping(address target => mapping(bytes4 selector => uint48 expiry)))) permissions;
```

to:

```solidity
mapping(address owner => mapping(address operator => mapping(address target => bytes auth))) permissions;
```

`auth` encoding:

```text
length == 0: no approval
length == 4: uint32 expiry only = full target approval
length > 4: uint32 expiry || sorted bytes4 selectors...
```

`uint32.max` is the stored permanent sentinel. The external API still returns `type(uint48).max` for permanent to preserve current semantics.

## Method

Foundry tests added in `test/AuthGasBench.t.sol`.

Commands:

```bash
# baseline
cd /tmp/erc-permissions-master
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://ethereum-rpc.publicnode.com -vvvv
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://base-rpc.publicnode.com -vvvv

# packed branch
cd /home/xiko/erc-permissions
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://ethereum-rpc.publicnode.com -vvvv
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://base-rpc.publicnode.com -vvvv
```

Mainnet and Base fork execution gas was identical for these local EVM operations. Base still differs economically because calldata/L1 data fees matter; Foundry's in-test `gasleft()` measurements do not include Base's separate L1 data fee component.

## Results: current selector => expiry baseline

```text
checkBatchWorst n=1   2,098
checkBatchWorst n=2   2,098
checkBatchWorst n=3   2,098
checkBatchWorst n=6   2,098
checkBatchWorst n=7   2,099
checkBatchWorst n=10  2,098
checkBatchWorst n=20  2,098
checkBatchWorst n=40  2,098
checkSingle           2,125

grantBatchFresh n=1      32,050
grantBatchFresh n=2      58,311
grantBatchFresh n=3      84,572
grantBatchFresh n=6     163,357
grantBatchFresh n=7     189,620
grantBatchFresh n=10    268,409
grantBatchFresh n=20    531,062
grantBatchFresh n=40  1,056,471
grantSingleFresh         35,311
```

## Results: packed bytes branch

```text
checkFull              2,633
grantFullFresh        35,780

checkBundleWorst n=1   3,137
checkBundleWorst n=2   3,403
checkBundleWorst n=3   3,669
checkBundleWorst n=6   4,467
checkBundleWorst n=7   5,161
checkBundleWorst n=10  6,039
checkBundleWorst n=20  8,506
checkBundleWorst n=40 13,637

grantBundleFresh n=1      37,495
grantBundleFresh n=2      40,914
grantBundleFresh n=3      44,333
grantBundleFresh n=6      54,591
grantBundleFresh n=7      80,239
grantBundleFresh n=10    112,658
grantBundleFresh n=20    169,040
grantBundleFresh n=40    303,995
```

The packed branch's legacy `grantBatch` path is not the optimized path, but was also measured:

```text
grantBatchFresh n=20 367,323
checkBatchWorst n=20   8,316
```

## Comparison

Approval writes:

```text
n=1:  packed bundle is +5,445 gas / +17.0% vs current batch
n=2:  packed bundle is -17,397 gas / -29.8%
n=3:  packed bundle is -40,239 gas / -47.6%
n=6:  packed bundle is -108,766 gas / -66.6%
n=7:  packed bundle is -109,381 gas / -57.7%
n=10: packed bundle is -155,751 gas / -58.0%
n=20: packed bundle is -362,022 gas / -68.2%
n=40: packed bundle is -752,476 gas / -71.2%
```

Runtime checks:

```text
current selector check: ~2,098 gas, O(1)
packed full approval:   ~2,633 gas, O(1), +535 gas vs current
packed selector bundle:
  n=1:  3,137 gas, +1,039
  n=6:  4,467 gas, +2,369
  n=20: 8,506 gas, +6,408
  n=40: 13,637 gas, +11,539
```

## Interpretation

The full-approval mode is the interesting result. It gives the likely forwarder case a single-slot approval and an O(1) check. In this draft implementation, the full check is about 535 gas more expensive than the current selector mapping check, while the approval cost is roughly equal to a single selector approval.

Selector bundles are much cheaper to approve for more than one selector, but they make checks O(n). This is acceptable for occasional/admin permissions, but expensive for frequently-called forwarder paths.

## Recommendation

The packed model is worth pursuing if full target approval is acceptable as a first-class permission mode.

Recommended canonical semantics:

```text
bytes auth = uint32 expiry || optional bytes4 selectors

length 0: no approval
length 4: full target approval
length >4: selector-scoped approval list
```

For forwarders, recommend full approval. For safety-sensitive partial delegation, use selector bundles and keep them small. If hot partial delegation is a major requirement, the current selector => expiry mapping remains better.

Potential next optimization: store/check the short bytes path entirely in assembly and avoid memory copies. The branch already special-cases short storage reads, but further hand-optimization may reduce the ~535 gas full-check delta.
