# Ethereum Magicians draft post

## Title options

1. Draft ERC: Scoped delegated authorization registry (full-target + selector-bundle approvals)
2. Draft ERC: A shared authorization primitive for delegated execution without custody
3. Draft ERC: Permission Registry — function-scoped delegation for forwarders, bots, and intents
4. Draft ERC: Approval Registry for selector-scoped operator permissions

Leaning toward (1) — it names the primitive and both modes in one line.

## Post body

Hi everyone,

I’m working on a draft ERC for a registry-based delegated authorization primitive and would love feedback before opening the EIP PR.

- Repo: https://github.com/yolo-maxi/erc-approval-registry
- Spec: https://github.com/yolo-maxi/erc-approval-registry/blob/master/SPEC.md
- Gas analysis: https://github.com/yolo-maxi/erc-approval-registry/blob/master/Gas%20analysis.md

## Problem

A lot of DeFi and automation flows need delegated execution without custody transfer: compounding bots, forwarders, social-trading agents, wrapper contracts that let an operator manage one specific position.

Today the usual options aren’t great:

- ERC-20 approvals are asset-scoped, not action-scoped.
- Vault custody solves authorization by moving assets into another contract.
- Per-protocol operator systems aren’t composable and aren’t consistently visible to wallets/indexers.
- Fully generic execution permissions are hard to render safely.

The goal is a small registry primitive that contracts can integrate with one authorization check and that wallets/indexers can display consistently.

## Proposed primitive

The registry stores one authorization blob per `(owner, operator, target)`:

```text
auth.length == 0: no approval
auth.length == 4: expiry only = full-target approval
auth.length > 4:  uint32 expiry || sorted bytes4 selectors...
```

So an owner can grant an operator either full approval on a target until expiry, or approval for a sorted bundle of specific selectors until expiry. Expiry is bundle-wide for each `(owner, operator, target)` — intentionally not per-selector, to keep the blob compact.

Integration is one modifier:

```solidity
modifier onlyAuthorized(address owner) {
    if (msg.sender != owner) {
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }
    _;
}
```

The target contract doesn’t care which mode the user picked — it just asks whether the caller is authorized for `msg.sig`.

## Why full-target approval is first-class

An earlier draft used a pure selector mapping (`owner → operator → target → selector → expiry`). That gives flat O(1) checks but makes broad delegation expensive — every selector is its own storage slot.

For trusted forwarders, broad target-level delegation is the common case. Encoding it as an expiry-only 4-byte blob gives one compact approval, O(1) checks, and gas roughly comparable to an ERC-20 approval. Selector bundles remain available when narrower scope is wanted.

## Gas tradeoff

Reference implementation, execution gas:

| | check | grant |
|---|---|---|
| Old selector mapping (1 selector) | ~2.1k | ~35.3k |
| Packed full-target | ~2.6k | ~35.8k |
| Packed bundle, 2 selectors | ~3.4k | ~40.9k (vs ~58.3k mapping) |
| Packed bundle, 6 selectors | ~4.5k | ~54.6k (vs ~163k mapping) |
| Packed bundle, 20 selectors | ~8.5k | ~169k (vs ~531k mapping) |
| ERC-20 `approve` reference | ~2.9k | ~31.4k |

Full-target approval is in ERC-20-approval territory. Selector bundles beat per-selector storage from 2 selectors onward but pay an O(n) check cost. In practice partial delegation tends to be "a few selectors or the whole target," so bundles in the 2–5 range are the expected shape.

## Selector sorting

Selector bundles must be strictly sorted and unique. The registry rejects unsorted/duplicate input rather than sorting onchain — sorting belongs in wallets/SDKs, and the registry gets deterministic encoding and early-exit checks.

## Expiry

External API uses `uint48`:

- `0` → revoked / not set
- `type(uint48).max` → permanent
- anything else → Unix timestamp

The reference implementation stores expiry compactly as `uint32` (permanent sentinel `uint32.max`, finite timestamps valid until 2106). This keeps full-target approvals at 4 bytes.

## EIP-712 permit

A selector-scoped EIP-712 permit lets an owner grant or revoke a single selector without sending a transaction themselves. Permits are intentionally selector-scoped; full-target approvals should require an explicit on-chain call so wallets can warn appropriately.

## Questions for feedback

1. Is full-target approval acceptable as a first-class primitive if wallets clearly distinguish it from selector-scoped approvals?
2. Should the standard recommend a maximum selector-bundle size?
3. Is `uint32` expiry inside the packed bytes acceptable given the permanent sentinel and the 2106 finite horizon?
4. Is the current event model enough for indexers, or should it carry more state?
5. Should `permitPermission` stay selector-scoped only, or also support full-target?

Thanks — looking for design feedback before turning this into a formal EIP PR.
