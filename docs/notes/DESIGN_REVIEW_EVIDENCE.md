# Design Review: Evidence Module

## Overview
The Evidence module provides a mechanism for structural counterexample tracking and evidence preservation in the programming-in-the-large framework. It enables the agent to learn from failed experiments by storing structural representations of changes that led to failures, preventing the repetition of the same mistakes.

## Core Components

### StructuralRep
A newtype wrapper that stores a structural representation of a code change derived from TreeSitter AST root node string representation. Provides:
- `Eq` instance for exact matching based on root node string
- `Show` instance for debugging/logging
- `Hashable` instance for efficient storage in hash maps

### Evidence
Represents a single piece of evidence:
- `evidenceChange`: The structural representation of the failed change (String from TreeSitter)
- `evidenceReason`: Why the change failed (TypeError, Divergence, MissingInstance, or OtherReason)
- `evidenceContext`: The institution signature this evidence belongs to

### EvidenceStore
A collection of evidence for a given signature, implemented as a HashMap from StructuralRep to Evidence. Provides:
- Monoid and Semigroup instances for combining stores
- Functions to add evidence, check for known failures, and retrieve evidence

### Key Functions
- `proposesKnownFailure`: Checks if a change matches any known failure
- `getEvidence`: Retrieves evidence for a structural representation
- `checkProposal`: Determines if a proposal is safe or conflicts with known evidence
- `recordFailure`: Records a new piece of evidence after a failed change
- `proposeChange`: Wrapper that checks a proposal against the evidence store

### Typeclass
- `ToStructuralRep`: Converts values to StructuralRep (with instance for TS.Tree that extracts root node string via unsafePerformIO)

## Integration with TreeSitter
The module integrates with the `hs-tree-sitter` package to:
1. Parse code changes into ASTs
2. Extract structural representations from AST root nodes via `treeRootNode` and `showNodeAsString`
3. Provide Eq/Show/Hashable based on the string representation of the root node
4. Uses `unsafePerformIO` to extract pure values from IO operations for the instances (acceptable for this sketch phase)

## Usage Example
```haskell
-- Create an empty evidence store
let store = emptyEvidenceStore :: EvidenceStore FirstOrderSig

-- After a failed change, record the evidence
let updatedStore = recordFailure failedChange (TypeError "Missing Eq constraint") proxy store

-- Before attempting a new change, check against evidence
case proposeChange newChange proxy updatedStore of
  Left evidence -> -- Known failure, avoid this change
  Right _ ->      -- Safe to try
```

## Design Decisions
1. **Structural Representation**: Uses string representation of TreeSitter root node via `unsafePerformIO` to extract pure values. This provides actual AST-based evidence rather than placeholder Strings.
2. **Unsafe IO**: Uses `unsafePerformIO` to extract TreeSitter representations for pure instances. Acceptable for this sketch phase as the values are deterministic and we're working with immutable ASTs.
3. **Failure Reasons**: Extensible algebraic data type for categorizing failures.
4. **Institution-Agnostic**: Works with any signature via phantom type parameter.

## Current Limitations
- Structural representation extracts only the root node string (could use full tree representation)
- No actual similarity checking (only exact structural rep matches) - should integrate tree-diff for structural similarity
- Uses `unsafePerformIO` which is acceptable for this phase but should be reconsidered for production
- No persistence mechanism (evidence is lost between runs) - could be saved to disk or database

## Conformance to Requirements
- ✅ Provides evidence preservation mechanism for autonomous coding
- ✅ Supports structural counterexample tracking using actual tree-sitter ASTs
- ✅ Integrates with existing Institution framework
- ✅ Written in Haskell with appropriate extensions
- ✅ Builds and tests successfully with the rest of the project

## Future Work
1. Enhance StructuralRep to use full tree representation or subtree matching
2. Integrate tree-diff for structural similarity checking (not just exact matches)
3. Replace unsafePerformIO with a safer approach or encapsulate the IO in the workflow
4. Add persistence layer to save/load evidence stores between sessions
5. Connect to actual build/test sandbox to automatically record failures
6. Integrate with CEGIS framework for guided synthesis using evidence