# Chapter 4: The End-to-End Sheaf-Gated CEGIS Loop

**Volume V:** Grounded Verification & Autonomous CEGIS  
**GHC Note Invariant:** Note [End-to-End Sheaf-Gated CEGIS Synthesis Loop] [ref:note-sheaf-gated-cegis-loop]  
**Production Function:** [`runSheafGatedCEGIS`](../../../../packages/gargamelle-workflow/src/Workflow/Synthesis.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-workflow/docs/Workflow-Synthesis.html#v:runSheafGatedCEGIS))

---

## 1. The Full Synthesis Cycle

The complete synthesis pipeline unifies all five volumes into a single continuous loop:

```mermaid
sequenceDiagram
    participant Agent as Synthesizer Agent (sarutahiko)
    participant Bwrap as Bubblewrap Sandbox (/usr/bin/bwrap)
    participant DB as Beam SQLite Database
    participant Sheaf as Cellular Sheaf Cohomology (&delta;<sup>0</sup>)

    Agent->>Bwrap: Execute candidate patch under private mount/PID
    alt Execution Fails / Times out
        Bwrap-->>DB: Store CounterexampleRecordT
        DB-->>Agent: Refined negative constraints for next hypothesis
    else Execution Succeeds
        Bwrap-->>DB: Store EvidenceRecordT
        Agent->>Sheaf: Evaluate coboundary &delta;<sup>0</sup> on multi-module cell complex
        alt H<sup>1</sup> &ne; 0 (Obstructions Detected)
            Sheaf-->>Agent: locateObstructions &rarr; failing boundary interfaces
            Note over Agent: Target repair strictly to failing interface
        else H<sup>1</sup> = 0 (Harmonic Consensus)
            Sheaf-->>Agent: Certified global section H<sup>0</sup>
            Note over Agent: Synthesis Verified Complete
        end
    end
```

---

## 2. Knaster-Tarski Diffusion Reconciliation

Prior to declaring a persistent boundary error, [`runSheafGatedCEGISWithDiffusion`](../../../../packages/gargamelle-workflow/src/Workflow/Synthesis.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-workflow/docs/Workflow-Synthesis.html#v:runSheafGatedCEGISWithDiffusion)) applies Store comonad cellular diffusion:

```haskell:ignore
runSheafGatedCEGISWithDiffusion :: SynthesisInput -> IO SynthesisOutput
```

If the interface mismatch is merely transient or reconcilable through contract meet semi-lattices, Knaster-Tarski diffusion converges to a greatest lower bound agreement without requiring expensive code re-synthesis. If persistent discrepancies remain ($H^1 \neq 0$), the precise obstruction is pinpointed via `locateObstructions` and fed back to the generative agent.

This completes the synthesis loop, delivering an autonomous, mathematically certified programming engine.
