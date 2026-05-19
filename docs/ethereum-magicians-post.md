# Ethereum Magicians draft post

Title suggestion:

Draft ERC: Scoped delegated authorization registry for full-target and selector-bundle approvals

## Post body

Hi everyone,

I’m working on a draft ERC for a registry-based delegated authorization primitive and would love feedback before submitting the EIP PR.

Repository:
https://github.com/yolo-maxi/erc-approval-registry

Draft spec:
https://github.com/yolo-maxi/erc-approval-registry/blob/master/SPEC.md

Gas analysis:
https://github.com/yolo-maxi/erc-approval-registry/blob/master/Gas%20analysis.md

## Problem

A lot of DeFi and automation flows need delegated execution without custody transfer.

Examples:

- A compounding bot claims and reinvests rewards.
- A forwarder submits actions on behalf of a user.
- A social/trading agent rebalances a position.
- A protocol wrapper lets an operator manage one specific account/position.

Today the usual choices are not great:

- ERC20 approvals are asset-scoped, not action-scoped.
- Vault custody solves authorization by moving assets into another contract.
- Protocol-specific operator systems are not composable or consistently visible to wallets/indexers.
- Fully generic execution permissions are hard to render safely.

The goal here is a small registry primitive that contracts can integrate with one authorization check, and that wallets/indexers can display consistently.

## Proposed primitive

The registry stores authorization per:

```text
owner -> operator -> target -> auth bytes
```

The `auth` bytes encode either full-target approval or a selector bundle:

```text
auth.length == 0: no approval
auth.length == 4: expiry only = full-target approval
auth.length > 4: uint32 expiry || sorted bytes4 selectors...
```

So an owner can grant an operator either:

- full approval on a target contract until expiry, or
- approval for a sorted bundle of specific function selectors until expiry.

Expiry is bundle-wide for each `(owner, operator, target)`. This keeps the primitive compact, but it intentionally does not support different expiries per selector inside the same bundle.

The target contract integration pattern is intentionally simple:

```solidity
modifier onlyAuthorized(address owner) {
    if (msg.sender != owner) {
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }
    _;
}
```

The integrating contract does not need to know whether the user granted full-target approval or a selector bundle. It just asks the registry whether the caller is authorized for `msg.sig`.

## Why include full-target approval?

Initially we explored a pure selector mapping:

```text
owner -> operator -> target -> selector -> expiry
```

That gives very cheap O(1) checks, but it makes broad delegation expensive because each selector writes its own storage slot.

For trusted forwarders, broad target-level delegation is likely the common case. Encoding full-target approval as an expiry-only blob gives that path:

- one compact approval
- O(1) authorization checks
- gas roughly comparable to an ERC20 approval

Selector bundles remain available when users/protocols want narrower permissions.

## Tradeoff

The tradeoff is that selector-bundle checks are O(n) in the number of selectors scanned.

Measured in the reference implementation:

- current selector-mapping check: about 2.1k gas, flat
- packed full-target check: about 2.6k gas, flat
- packed selector-bundle check, 6 selectors worst-case: about 4.5k gas
- packed selector-bundle check, 20 selectors worst-case: about 8.5k gas
- packed selector-bundle check, 40 selectors worst-case: about 13.6k gas

Selector-bundle approvals are much cheaper than writing one storage slot per selector. For example, in the reference implementation:

- 2 selectors: about 40.9k gas vs 58.3k for selector mapping
- 6 selectors: about 54.6k gas vs 163.4k
- 20 selectors: about 169k gas vs 531k
- 40 selectors: about 304k gas vs 1.06M

Full-target approval is the forwarder path:

- grant: about 35.8k gas
- check: about 2.6k gas

A minimal ERC20 approval benchmark was about 31.4k execution gas, so full-target approval is in the same general cost range.

## Selector sorting

Selector bundles are required to be strictly sorted and unique.

The contract rejects unsorted or duplicate selectors instead of sorting onchain. Sorting can be done by wallets/SDKs/offchain tooling, while the registry gets deterministic encoding and early-exit checks.

## Expiry

The external API uses `uint48` expiry semantics:

- `0` means revoked / not set
- `type(uint48).max` means permanent
- any other value is a Unix timestamp

The reference implementation stores expiry compactly as `uint32` inside the auth bytes:

- `uint32.max` is the internal permanent sentinel
- finite timestamps are valid until February 2106

This keeps full-target approvals at 4 bytes and selector bundles compact.

## EIP-712 permit

The draft includes a selector-scoped EIP-712 permit flow so an owner can grant or revoke a selector permission without submitting the transaction themselves.

The permit is intentionally selector-scoped. Full-target approvals should use an explicit full-approval flow so wallets can display stronger warnings.

## Questions for feedback

I’d especially appreciate feedback on:

1. Is full-target approval acceptable as a first-class primitive if wallets clearly distinguish it from selector-scoped approvals?
2. Should the standard include a maximum recommended selector-bundle size?
3. Is `uint32` expiry inside the packed bytes acceptable given the permanent sentinel and the year-2106 finite timestamp horizon?
4. Should the event model expose more information for indexers, or is `rawPermissionData(owner, operator, target)` enough?
5. Should full-target signed permits be included, or is it better to keep permits selector-scoped for safer wallet UX?

Thanks — looking for design feedback before turning this into a formal EIP PR.
