const problemPoints = [
  "Smart account permission systems are powerful but fragment UX, trust assumptions, and integration effort.",
  "Most delegated flows still rely on app-specific approvals or full custody handoffs instead of explicit, narrow rights.",
  "Protocols want better automation and richer LP tooling, but they do not want to become wallet infrastructure companies.",
];

const pillars = [
  {
    title: "Registry-first",
    body:
      "Permissions live in a shared registry keyed by owner, operator, target, and selector. Integrators query one canonical place instead of inventing bespoke auth layers.",
  },
  {
    title: "Modifier-based integration",
    body:
      "Contracts opt in with lightweight permission-aware modifiers. The registry stays generic while protocol logic remains local and auditable.",
  },
  {
    title: "Clear-signing UX",
    body:
      "EIP-712 permits make rights explicit: who can call what, on which contract, until when, and with which nonce or calldata commitment.",
  },
  {
    title: "Non-custodial feature unlocks",
    body:
      "Wrappers and coordinators can add automation, rebalancing, batching, and fee workflows without taking possession of the user’s base assets.",
  },
];

const sections = [
  { id: "problem", label: "Problem" },
  { id: "why-now", label: "Why now" },
  { id: "how-it-works", label: "How it works" },
  { id: "architecture", label: "Architecture" },
  { id: "signing", label: "EIP-712 UX" },
  { id: "batching", label: "Batch permissions" },
  { id: "flows", label: "Example flows" },
  { id: "uniswap-v3", label: "Uniswap v3 wrapper" },
  { id: "uniswap-v4", label: "Uniswap v4 wrapper" },
  { id: "security", label: "Security" },
  { id: "adoption", label: "Adoption path" },
];

const permissionSnippet = `struct PermissionKey {
  address owner;
  address operator;
  address target;
  bytes4 selector;
}

registry.grant(operator, target, selector);
registry.revoke(operator, target, selector);

bool allowed = registry.isPermissioned(
  owner,
  operator,
  target,
  selector
);`;

const modifierSnippet = `modifier onlyAuthorized(address owner) {
  if (
    msg.sender != owner &&
    !registry.isAuthorizedCall(
      owner,
      msg.sender,
      address(this),
      msg.sig
    )
  ) {
    revert Unauthorized();
  }
  _;
}

function rebalance(
  address owner,
  RebalanceParams calldata params
) external onlyAuthorized(owner) {
  // protocol logic remains local
}`;

const permitSnippet = `PermissionPermit({
  owner: 0xA11CE..., 
  operator: 0xB0T..., 
  target: 0xWrapper..., 
  selector: 0x4f1ef286,
  approved: true,
  nonce: 12,
  deadline: 1714675200
})

ExecutionPermit({
  owner: 0xA11CE..., 
  operator: 0xB0T..., 
  target: 0xWrapper..., 
  selector: 0xaabbccdd,
  calldataHash: keccak256(callData),
  value: 0,
  nonce: 34,
  deadline: 1714678800
})`;

const batchSnippet = `PermissionKey[] memory keys = new PermissionKey[](3);
keys[0] = key(owner, bot, wrapper, IWrapper.rebalance.selector);
keys[1] = key(owner, bot, wrapper, IWrapper.collectFees.selector);
keys[2] = key(owner, bot, wrapper, IWrapper.compound.selector);

registry.grantBatch(keys);`;

function SectionHeading({
  eyebrow,
  title,
  body,
}: {
  eyebrow: string;
  title: string;
  body: string;
}) {
  return (
    <div className="max-w-3xl space-y-4">
      <p className="text-xs font-semibold uppercase tracking-[0.28em] text-cyan-300/80">
        {eyebrow}
      </p>
      <h2 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
        {title}
      </h2>
      <p className="text-base leading-8 text-slate-300 sm:text-lg">{body}</p>
    </div>
  );
}

function CodeBlock({ code }: { code: string }) {
  return (
    <pre className="overflow-x-auto rounded-3xl border border-white/10 bg-slate-950/90 p-5 text-sm leading-7 text-cyan-100 shadow-[0_0_0_1px_rgba(255,255,255,0.03)]">
      <code>{code}</code>
    </pre>
  );
}

function DiagramCard({
  title,
  steps,
}: {
  title: string;
  steps: { label: string; body: string }[];
}) {
  return (
    <div className="rounded-[28px] border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
      <p className="text-sm font-semibold uppercase tracking-[0.2em] text-cyan-300/70">
        {title}
      </p>
      <div className="mt-6 space-y-4">
        {steps.map((step, index) => (
          <div key={step.label} className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-cyan-400/30 bg-cyan-400/10 text-sm font-semibold text-cyan-200">
              {index + 1}
            </div>
            <div>
              <p className="font-medium text-white">{step.label}</p>
              <p className="mt-1 text-sm leading-7 text-slate-300">{step.body}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <main className="min-h-screen bg-[#020617] text-white">
      <div className="absolute inset-x-0 top-0 -z-0 h-[520px] bg-[radial-gradient(circle_at_top,rgba(34,211,238,0.22),transparent_52%),radial-gradient(circle_at_20%_20%,rgba(59,130,246,0.18),transparent_30%)]" />
      <div className="relative z-10 mx-auto max-w-7xl px-6 pb-24 pt-8 sm:px-10 lg:px-12">
        <header className="sticky top-0 z-20 mb-10 rounded-full border border-white/10 bg-slate-950/70 px-4 py-3 backdrop-blur-xl">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.25em] text-cyan-300">
                ERC Permissions
              </p>
              <p className="text-sm text-slate-400">
                Draft standard / reference implementation for generic delegated execution.
              </p>
            </div>
            <nav className="flex flex-wrap gap-3 text-sm text-slate-300">
              {sections.map((section) => (
                <a
                  key={section.id}
                  href={`#${section.id}`}
                  className="rounded-full border border-white/10 px-3 py-1.5 transition hover:border-cyan-400/40 hover:bg-white/5 hover:text-white"
                >
                  {section.label}
                </a>
              ))}
            </nav>
          </div>
        </header>

        <section className="grid gap-10 pb-20 pt-10 lg:grid-cols-[1.2fr_0.8fr] lg:items-end">
          <div className="space-y-8">
            <div className="inline-flex items-center rounded-full border border-cyan-400/20 bg-cyan-400/10 px-4 py-2 text-sm text-cyan-100">
              Narrow permissions, clearer signatures, richer automation.
            </div>
            <div className="space-y-6">
              <h1 className="max-w-4xl text-5xl font-semibold tracking-tight text-white sm:text-6xl lg:text-7xl">
                A registry-first permission layer for non-custodial protocol UX.
              </h1>
              <p className="max-w-3xl text-lg leading-8 text-slate-300 sm:text-xl">
                This site presents a draft ERC-style model for generic permissions: users grant or sign explicit rights for an operator to call a specific selector on a specific target, while protocols integrate through lightweight modifiers instead of bespoke custody or account abstraction stacks.
              </p>
            </div>
            <div className="flex flex-wrap gap-4">
              <a
                href="#how-it-works"
                className="rounded-full bg-cyan-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300"
              >
                Read the model
              </a>
              <a
                href="#uniswap-v3"
                className="rounded-full border border-white/15 px-5 py-3 text-sm font-semibold text-white transition hover:bg-white/5"
              >
                See wrapper examples
              </a>
            </div>
          </div>

          <div className="rounded-[32px] border border-white/10 bg-white/5 p-6 shadow-2xl shadow-cyan-950/30 backdrop-blur-xl">
            <div className="rounded-[24px] border border-cyan-400/20 bg-slate-950/80 p-5">
              <p className="text-sm font-semibold uppercase tracking-[0.22em] text-cyan-300/80">
                Reference shape
              </p>
              <div className="mt-5 space-y-4 text-sm text-slate-300">
                <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
                  <p className="font-medium text-white">Registry key</p>
                  <p className="mt-2 text-slate-400">
                    owner × operator × target × selector
                  </p>
                </div>
                <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
                  <p className="font-medium text-white">Permit UX</p>
                  <p className="mt-2 text-slate-400">
                    EIP-712 typed data for grants and single-execution signed intents.
                  </p>
                </div>
                <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
                  <p className="font-medium text-white">Integration</p>
                  <p className="mt-2 text-slate-400">
                    Protocol contracts gate functions with a registry-aware modifier.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section className="grid gap-5 pb-24 md:grid-cols-2 xl:grid-cols-4">
          {pillars.map((pillar) => (
            <div
              key={pillar.title}
              className="rounded-[28px] border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
            >
              <h3 className="text-xl font-semibold text-white">{pillar.title}</h3>
              <p className="mt-4 text-sm leading-7 text-slate-300">{pillar.body}</p>
            </div>
          ))}
        </section>

        <div className="space-y-24">
          <section id="problem" className="grid gap-10 lg:grid-cols-[0.9fr_1.1fr]">
            <SectionHeading
              eyebrow="Problem"
              title="Delegation is either too coarse, too bespoke, or too custodial."
              body="Today, users who want automation or richer position management usually choose between blunt approvals, app-specific operator models, or fully managed wrappers. None of those feel like the internet-native primitive we should standardize around."
            />
            <div className="space-y-4">
              {problemPoints.map((point) => (
                <div
                  key={point}
                  className="rounded-[28px] border border-white/10 bg-white/5 p-5 text-slate-300"
                >
                  {point}
                </div>
              ))}
            </div>
          </section>

          <section id="why-now" className="grid gap-10 lg:grid-cols-[1fr_1fr]">
            <SectionHeading
              eyebrow="Why now"
              title="Protocols want app-like UX without swallowing wallet complexity."
              body="Between intent systems, automation networks, hook-based protocols, and increasingly sophisticated LP products, the market is asking for a generic way to express narrowly scoped rights. A registry-first standard can provide that shared substrate without assuming universal smart accounts."
            />
            <DiagramCard
              title="Pressure from both sides"
              steps={[
                {
                  label: "Users expect automation",
                  body: "Rebalancing, fee compounding, stop-losses, and scheduled actions should not require trust-heavy wrappers or hand-managed multisigs.",
                },
                {
                  label: "Protocols need composability",
                  body: "If each app ships its own permission contract and signature format, wallets and integrators can never converge on a common UX surface.",
                },
                {
                  label: "Signatures are now a product surface",
                  body: "Typed data can expose intent clearly enough to become the user-facing control plane for delegated execution.",
                },
              ]}
            />
          </section>

          <section id="how-it-works" className="space-y-10">
            <SectionHeading
              eyebrow="How it works"
              title="A minimal model: explicit rights keyed by contract and function selector."
              body="The base primitive is intentionally narrow. A permission does not mean ‘this app can do things for me’. It means ‘this operator may call this function on this contract for my account context’, optionally via an EIP-712 signed one-shot execution permit with calldata commitment."
            />
            <div className="grid gap-6 lg:grid-cols-[1fr_1fr]">
              <CodeBlock code={permissionSnippet} />
              <DiagramCard
                title="Execution shape"
                steps={[
                  {
                    label: "Persistent grant",
                    body: "The owner writes or signs a permission entry in the registry. Future calls can be validated by the target modifier.",
                  },
                  {
                    label: "One-shot signed execution",
                    body: "For tighter UX, the owner signs a specific execution permit that binds selector, target, value, nonce, expiry, and calldata hash.",
                  },
                  {
                    label: "Protocol-level enforcement",
                    body: "The target contract remains in control of semantics. The registry only answers whether the caller is authorized for this edge in the graph.",
                  },
                ]}
              />
            </div>
          </section>

          <section id="architecture" className="space-y-10">
            <SectionHeading
              eyebrow="Architecture"
              title="Registry-first keeps shared authorization generic and protocol logic local."
              body="The reference architecture separates concerns cleanly: the registry stores permission facts and permit nonces, while integrating contracts decide how those permissions map onto application-specific state transitions. That makes the system easier to adopt incrementally and easier to audit in layers."
            />
            <div className="grid gap-6 lg:grid-cols-3">
              <DiagramCard
                title="Layer 1 · Registry"
                steps={[
                  {
                    label: "Canonical state",
                    body: "Stores granted edges, permit nonces, and active execution context for permission-aware downstream checks.",
                  },
                  {
                    label: "Shared verification",
                    body: "Handles EIP-712 domain separation, signature checks, nonces, deadlines, and calldata hash validation.",
                  },
                ]}
              />
              <DiagramCard
                title="Layer 2 · Integrator contracts"
                steps={[
                  {
                    label: "Modifiers / guards",
                    body: "A wrapper, vault, or manager contract checks owner-or-authorized before executing core logic.",
                  },
                  {
                    label: "Local semantics",
                    body: "The contract decides what ‘rebalance’, ‘collect’, or ‘close range’ actually means. The registry does not encode product behavior.",
                  },
                ]}
              />
              <DiagramCard
                title="Layer 3 · Wallet / app UX"
                steps={[
                  {
                    label: "Permission dashboards",
                    body: "Wallets can render active rights from a common registry instead of reverse engineering each app’s auth contract.",
                  },
                  {
                    label: "Signer prompts",
                    body: "Apps can present structured grant or execution requests that map directly to standardized typed data.",
                  },
                ]}
              />
            </div>
            <CodeBlock code={modifierSnippet} />
          </section>

          <section id="signing" className="space-y-10">
            <SectionHeading
              eyebrow="EIP-712 clear-signing UX"
              title="Delegation should be legible before it is powerful."
              body="The strongest UX advantage here is not raw gas efficiency — it is clarity. Signing should tell the user exactly which operator gains which ability, against which target, under which expiry and nonce. For one-shot execution, the prompt can further show the bound function and whether calldata is committed."
            />
            <div className="grid gap-6 lg:grid-cols-[1fr_0.95fr]">
              <CodeBlock code={permitSnippet} />
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <p className="text-sm font-semibold uppercase tracking-[0.2em] text-cyan-300/80">
                  What a wallet can show
                </p>
                <div className="mt-5 space-y-4 text-sm leading-7 text-slate-300">
                  <p>
                    <span className="font-medium text-white">Grant permission:</span> “Allow 0xB0T… to call <span className="text-cyan-200">rebalance()</span> on <span className="text-cyan-200">LPWrapper</span> until 2026-06-01.”
                  </p>
                  <p>
                    <span className="font-medium text-white">Execute one action:</span> “Authorize a single <span className="text-cyan-200">collectFees()</span> execution with calldata hash 0x12…ef and nonce 34.”
                  </p>
                  <p>
                    <span className="font-medium text-white">Revoke:</span> “Remove operator access for compound() on Wrapper X.”
                  </p>
                  <p>
                    Because the typed data structure is generic, wallets can build reusable signing UI instead of treating every protocol message as opaque bytes.
                  </p>
                </div>
              </div>
            </div>
          </section>

          <section id="batching" className="space-y-10">
            <SectionHeading
              eyebrow="Batch permissions"
              title="Real products need bundles, not dozens of separate prompts."
              body="A single strategy often needs a small set of tightly related abilities: rebalance, collect, compound, maybe emergency unwind. The reference interface therefore includes batch grant / revoke paths so a wallet or app can present a coherent capability bundle while still recording each permission edge explicitly."
            />
            <div className="grid gap-6 lg:grid-cols-[0.95fr_1.05fr]">
              <CodeBlock code={batchSnippet} />
              <DiagramCard
                title="Batching design goals"
                steps={[
                  {
                    label: "Few signatures",
                    body: "Users should authorize a strategy bundle once, not click through a long list of nearly identical prompts.",
                  },
                  {
                    label: "Explicit registry rows",
                    body: "Bundling is a UX convenience. On-chain state still resolves to individual owner/operator/target/selector entries.",
                  },
                  {
                    label: "Wallet reviewability",
                    body: "A wallet can render grouped capabilities like ‘LP management bundle’ while preserving precise revoke semantics per selector.",
                  },
                ]}
              />
            </div>
          </section>

          <section id="flows" className="space-y-10">
            <SectionHeading
              eyebrow="Example flows"
              title="Two practical operating modes: standing rights and signed one-shots."
              body="Different products need different risk envelopes. The same registry can support durable automation relationships and highly constrained one-off actions."
            />
            <div className="grid gap-6 lg:grid-cols-2">
              <DiagramCard
                title="Flow A · Standing automation"
                steps={[
                  {
                    label: "1. User opts in",
                    body: "The wallet grants a bot or coordinator permission to call a small set of wrapper selectors.",
                  },
                  {
                    label: "2. Bot monitors conditions",
                    body: "Off-chain logic watches price bands, fee accrual, or market schedules.",
                  },
                  {
                    label: "3. Wrapper executes",
                    body: "When needed, the operator calls the wrapper. The modifier checks the registry before the wrapper touches protocol state.",
                  },
                ]}
              />
              <DiagramCard
                title="Flow B · Signed exact action"
                steps={[
                  {
                    label: "1. App prepares calldata",
                    body: "The UI constructs the exact operation and hashes the calldata for replay-safe commitment.",
                  },
                  {
                    label: "2. User signs once",
                    body: "The signature authorizes one target + selector + calldataHash + nonce + deadline tuple.",
                  },
                  {
                    label: "3. Relayer or bot submits",
                    body: "Anyone can forward the call, but only the committed action succeeds.",
                  },
                ]}
              />
            </div>
          </section>

          <section id="uniswap-v3" className="space-y-10">
            <SectionHeading
              eyebrow="Uniswap v3 wrapper use case"
              title="Add automated range management without taking custody of the LP relationship."
              body="A v3 position wrapper is a concrete example of why this model matters. The wrapper can expose higher-level functions like rebalancePosition, collectAndCompound, or migrateTicks, while still anchoring authority in explicit owner-granted rights rather than a fully custodial strategy vault."
            />
            <div className="grid gap-6 lg:grid-cols-[1fr_1fr]">
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <h3 className="text-xl font-semibold text-white">What improves</h3>
                <ul className="mt-5 space-y-3 text-sm leading-7 text-slate-300">
                  <li>• Rebalance concentrated liquidity positions on policy triggers.</li>
                  <li>• Compound fees on cadence or thresholds.</li>
                  <li>• Separate strategy operation rights from token withdrawal rights.</li>
                  <li>• Let users revoke per-function access without unwinding the whole wrapper relationship.</li>
                </ul>
              </div>
              <DiagramCard
                title="Reference flow"
                steps={[
                  {
                    label: "User deposits position into wrapper context",
                    body: "The wrapper becomes the protocol-facing manager for the position, but the delegated operator only receives specific wrapper-level rights.",
                  },
                  {
                    label: "Registry authorizes rebalance() + compound()",
                    body: "The bot is not granted blanket transfer control; it is granted strategy methods only.",
                  },
                  {
                    label: "Withdraw remains owner-only or separately gated",
                    body: "The most sensitive exits can remain outside the delegated bundle entirely.",
                  },
                ]}
              />
            </div>
          </section>

          <section id="uniswap-v4" className="space-y-10">
            <SectionHeading
              eyebrow="Uniswap v4 wrapper use case"
              title="Hooks and programmable pools make fine-grained delegated permissions even more valuable."
              body="With v4-style hook systems and more modular pool behavior, LP products can become dramatically more expressive. A registry-first permission layer is useful here because wrappers, hook managers, and coordinators may need multiple narrow capabilities that should remain understandable and revocable."
            />
            <div className="grid gap-6 lg:grid-cols-3">
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <h3 className="text-lg font-semibold text-white">Hook-aware managers</h3>
                <p className="mt-4 text-sm leading-7 text-slate-300">
                  A manager contract can receive permission to update liquidity or trigger maintenance paths while keeping swap settlement and withdrawals outside its authority envelope.
                </p>
              </div>
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <h3 className="text-lg font-semibold text-white">Composable coordinators</h3>
                <p className="mt-4 text-sm leading-7 text-slate-300">
                  Different services can coordinate around the same position or wrapper because authorization resolves against one generic registry rather than fragmented app-specific auth contracts.
                </p>
              </div>
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <h3 className="text-lg font-semibold text-white">Better product surfaces</h3>
                <p className="mt-4 text-sm leading-7 text-slate-300">
                  Apps can offer “activate auto-range + fee sweeps + safety unwind” as a bundle while still exposing exact underlying selectors to wallets and revoke dashboards.
                </p>
              </div>
            </div>
          </section>

          <section id="security" className="space-y-10">
            <SectionHeading
              eyebrow="Security / trust model"
              title="The registry narrows trust — it does not eliminate it."
              body="This proposal should be read as a reference implementation and draft standard direction, not as a claim that permissions become magically safe. Security comes from narrow scope, strong typed-data UX, replay protection, audited integration points, and disciplined separation between strategy methods and value-extraction methods."
            />
            <div className="grid gap-6 lg:grid-cols-2">
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <h3 className="text-xl font-semibold text-white">What the model helps with</h3>
                <ul className="mt-5 space-y-3 text-sm leading-7 text-slate-300">
                  <li>• Explicit least-privilege delegation by selector.</li>
                  <li>• Replay resistance through nonces and deadlines.</li>
                  <li>• Optional calldata commitment for exact-action signatures.</li>
                  <li>• Shared visibility for wallets and revoke tooling.</li>
                </ul>
              </div>
              <div className="rounded-[28px] border border-white/10 bg-white/5 p-6">
                <h3 className="text-xl font-semibold text-white">What still requires care</h3>
                <ul className="mt-5 space-y-3 text-sm leading-7 text-slate-300">
                  <li>• A bad wrapper can still misuse the rights it was legitimately granted.</li>
                  <li>• Selector-level granularity may need additional parameter constraints for some products.</li>
                  <li>• Wallets must render typed data well; opaque signing would undercut the entire point.</li>
                  <li>• Protocols need careful function design so powerful operations are not hidden behind overly broad entrypoints.</li>
                </ul>
              </div>
            </div>
          </section>

          <section id="adoption" className="space-y-10">
            <SectionHeading
              eyebrow="Adoption path"
              title="Start as reference code, converge into shared tooling, then standardize where usage proves out."
              body="The practical path is incremental. Ship a small reference registry, integrate it into one or two wrappers, let wallets experiment with permission rendering, and only then harden the typed data and interface details into a broader standardization effort. The value comes from convergence and ergonomics, not from claiming finality too early."
            />
            <div className="grid gap-6 lg:grid-cols-3">
              <DiagramCard
                title="Phase 1"
                steps={[
                  {
                    label: "Reference implementation",
                    body: "Publish registry contracts and a minimal modifier pattern for early integrations.",
                  },
                ]}
              />
              <DiagramCard
                title="Phase 2"
                steps={[
                  {
                    label: "Wallet / app experiments",
                    body: "Standardize how grants, bundles, and exact execution permits are displayed to users.",
                  },
                ]}
              />
              <DiagramCard
                title="Phase 3"
                steps={[
                  {
                    label: "Draft ERC maturation",
                    body: "Refine message schemas, revoke semantics, and extension points once real integrator feedback exists.",
                  },
                ]}
              />
            </div>
          </section>
        </div>
      </div>
    </main>
  );
}
