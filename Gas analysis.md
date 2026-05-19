# Gas analysis

This note compares the current selector-mapping design against the packed-auth-bytes variation.

## Designs compared

### Current design: selector mapping

Storage shape:

```solidity
mapping(address owner => mapping(address operator => mapping(address target => mapping(bytes4 selector => uint48 expiry)))) permissions;
```

Semantics:

- Each approved selector gets its own storage slot.
- `expiry == 0` means not approved / revoked.
- `expiry == type(uint48).max` means permanent.
- Any other nonzero expiry is a Unix timestamp.

Hot-path check:

- Lookup exactly one selector slot.
- Check expiry.
- Constant-time / O(1), regardless of how many selectors were approved.

### Packed-auth-bytes variation

Storage shape:

```solidity
mapping(address owner => mapping(address operator => mapping(address target => bytes auth))) permissions;
```

Suggested encoding:

```text
auth.length == 0: no approval
auth.length == 4: full target approval, expiry only
auth.length > 4: uint32 expiry || sorted bytes4 selectors...
```

Where:

- The first 4 bytes are a `uint32` Unix timestamp expiry.
- `uint32.max` is the permanent approval sentinel.
- If only the 4-byte expiry is present, the operator is approved for all selectors on the target.
- If selectors are present, the operator is approved only for those selectors.
- Selectors should be sorted and unique to allow early exit during scans.

Hot-path check:

- Load the auth blob for `(owner, operator, target)`.
- Check expiry.
- If the blob is expiry-only, return true for any selector.
- Otherwise iterate over the sorted selector list until match or early exit.

## Measurement method

Foundry gas tests were added in `test/AuthGasBench.t.sol` on the packed branch, then mirrored into a temporary `origin/master` worktree for baseline measurement.

Commands used:

```bash
# Current selector-mapping baseline
cd /tmp/erc-permissions-master
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://ethereum-rpc.publicnode.com -vvvv
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://base-rpc.publicnode.com -vvvv

# Packed-auth-bytes branch
cd /home/xiko/erc-permissions
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://ethereum-rpc.publicnode.com -vvvv
/home/xiko/.foundry/bin/forge test --match-contract AuthGasBench --fork-url https://base-rpc.publicnode.com -vvvv
```

Mainnet and Base fork execution gas was identical for these local EVM operations.

Important caveat for Base:

- The measured execution gas is identical.
- The real transaction fee on Base also includes L1 data / calldata costs.
- Foundry `gasleft()` measurements inside the test do not include that separate L1 fee component.
- For this comparison, the execution-gas tradeoff is still meaningful because the storage/check logic is the part being compared.

## Results: ERC20 approval reference

A minimal ERC20 `approve(spender, amount)` was benchmarked separately using the same `gasleft()` style.

Execution gas:

- `approve`, zero → nonzero: about 31.4k gas
- `approve`, nonzero → nonzero: about 2.9k gas
- `approve`, nonzero → zero: about 2.9k gas in the local measurement, before considering refund accounting nuances

Comparison anchor:

- Current registry single-selector grant: about 35.3k gas
- Packed full-target grant: about 35.8k gas

Conclusion:

A full-target approval in the packed model is very close to ERC20 approval territory. It is slightly more expensive than a minimal ERC20 approval, but the same order of magnitude.

## Results: current selector-mapping design

Approval costs, fresh storage:

- 1 selector: about 32.1k gas via `grantBatch`, or about 35.3k via single `grant`
- 2 selectors: about 58.3k gas
- 3 selectors: about 84.6k gas
- 6 selectors: about 163.4k gas
- 7 selectors: about 189.6k gas
- 10 selectors: about 268.4k gas
- 20 selectors: about 531.1k gas
- 40 selectors: about 1.06M gas

Check costs:

- Single selector check: about 2.1k gas
- Batch size does not matter for checks.
- Checking one selector remains about 2.1k gas even if 40 selectors have been approved.

Interpretation:

The current model is excellent for hot-path execution. It is constant-time and predictable. The tradeoff is that approvals scale linearly with the number of selectors because each selector writes a separate storage slot.

## Results: packed-auth-bytes design

Full-target approval:

- Fresh full-target grant: about 35.8k gas
- Full-target check: about 2.63k gas

Selector-bundle approval, fresh storage:

- 1 selector: about 37.5k gas
- 2 selectors: about 40.9k gas
- 3 selectors: about 44.3k gas
- 6 selectors: about 54.6k gas
- 7 selectors: about 80.2k gas
- 10 selectors: about 112.7k gas
- 20 selectors: about 169.0k gas
- 40 selectors: about 304.0k gas

Worst-case selector-bundle check, selector last in the bundle:

- 1 selector: about 3.14k gas
- 2 selectors: about 3.40k gas
- 3 selectors: about 3.67k gas
- 6 selectors: about 4.47k gas
- 7 selectors: about 5.16k gas
- 10 selectors: about 6.04k gas
- 20 selectors: about 8.51k gas
- 40 selectors: about 13.64k gas

Interpretation:

The full-target path is the important result for forwarders. It has approximately ERC20-approval-like grant cost, and the check remains O(1). The check is about 535 gas more than the current selector-mapping check in the tested implementation, which is very small in absolute terms.

Selector bundles are much cheaper to approve than the current selector-mapping batch once more than one selector is involved. However, selector-bundle checks are O(n), and their cost depends on the number of selectors scanned.

## Direct comparison

### Approval cost

For selector bundles, compared to the current selector-mapping batch:

- 1 selector: packed bundle is about 5.4k gas more expensive
- 2 selectors: packed bundle saves about 17.4k gas
- 3 selectors: packed bundle saves about 40.2k gas
- 6 selectors: packed bundle saves about 108.8k gas
- 7 selectors: packed bundle saves about 109.4k gas
- 10 selectors: packed bundle saves about 155.8k gas
- 20 selectors: packed bundle saves about 362.0k gas
- 40 selectors: packed bundle saves about 752.5k gas

So for approval transactions, the packed selector bundle starts winning at 2 selectors.

For full-target approvals:

- Current design has no equivalent full-target primitive.
- The closest current equivalent would be approving every selector individually, which becomes expensive quickly.
- Packed full-target approval costs about the same as one normal selector grant.

### Check cost

Current selector mapping:

- About 2.1k gas.
- Constant-time.
- Best for hot partial permissions.

Packed full-target approval:

- About 2.63k gas.
- Constant-time.
- About 535 gas more expensive than current selector mapping.
- Still extremely low and likely acceptable for forwarder paths.

Packed selector bundle:

- O(n) in the number of selectors scanned.
- Worst-case check at 20 selectors was about 8.5k gas.
- Worst-case check at 40 selectors was about 13.6k gas.
- Still not huge in absolute terms, but meaningfully more than the current O(1) mapping check.

## Tradeoffs

### Current selector-mapping design

Strengths:

- Best hot-path check cost.
- Check cost is constant and predictable.
- Simple authorization semantics: one selector, one expiry.
- Easy to reason about for integrators.
- Ideal when permissions are checked very frequently and only partial delegation is desired.

Weaknesses:

- Multi-selector approvals are expensive.
- Approving many selectors requires many storage writes.
- No cheap native representation for “operator can call any function on this target”.
- Forwarder-style “delegate everything” use cases either require many selector approvals or a separate concept.

Best fit:

- Hot partial permissions.
- Safety-sensitive narrow delegation.
- Cases where execution gas matters more than approval gas.

### Packed-auth-bytes design

Strengths:

- Full-target approval is very cheap: roughly ERC20 approval territory.
- Full-target checks remain O(1) and cheap.
- Selector bundles are much cheaper to approve than separate mapping slots once there is more than one selector.
- One canonical storage representation can express no approval, full approval, and selector-bundle approval.
- Good UX for forwarders where the user likely wants to delegate the whole target.

Weaknesses:

- Selector-bundle checks are O(n).
- Hot partial permissions become more expensive as bundle size grows.
- The implementation is more subtle than a simple nested mapping.
- Expiry is naturally bundle-wide, not per selector.
- Uses `uint32` expiry internally, which is fine until February 2106 but shorter than the current `uint48` timestamp range.

Best fit:

- Forwarders and operators that should have full target-level delegation.
- UX-friendly multi-selector approvals.
- Cases where approval gas matters and checks are not extremely hot.
- Protocols that can clearly display full-target approval risk to users.

## Recommendation

The packed-auth-bytes design looks attractive if full-target approval is accepted as a first-class primitive.

The forwarder case is the strongest argument:

- Users often want to authorize a trusted forwarder/operator to perform any supported action on a target.
- Packed full-target approval costs about the same as one selector approval.
- The check remains O(1), avoiding the hot-path problem.
- The cost is comparable to a standard ERC20 approval.

Selector bundles should be treated as the narrower, more explicit alternative:

- They are cheaper to grant than current batch approvals.
- They are more expensive to check than current selector mapping.
- The costs remain low in absolute terms for reasonable bundle sizes.

A clean way to frame the packed design is:

```text
Full approval: cheap, O(1), best for trusted forwarders.
Selector bundle: narrower, cheaper to approve than mapping batches, O(n) to check.
No approval: empty bytes.
```

Given the measured costs, all variants are reasonably cheap in absolute terms. The packed-auth-bytes approach gives a better UX/gas profile for broad forwarder delegation while preserving selector-level restriction when desired.

## Open questions

- Should full-target approval be allowed by the standard, or only by implementations that opt in?
- Should selector bundles have a maximum recommended size?
- Should the standard require sorted unique selectors?
- Should `uint32.max` represent permanent approval, or should permanent approvals be avoided?
- Should wallets be required/recommended to display full-target approval with stronger warnings than selector-specific approvals?
