# Design Review: Evidence Module

## Overview
This document reviews the Evidence module implementation in the programming-in-the-large project. The module provides a mechanism for preserving evidence of failed experiments to prevent repeating the same mistakes in autonomous coding workflows.

## Purpose
The Evidence module implements structural counterexample tracking and evidence preservation as described in the gemini-scaling-autonomous-coding transcript. It allows the system to:
1. Record failed code changes with their structural representation and failure reason
2. Prevent reuse of changes that are known to fail for the same structural reasons
3. Support autonomous agents in navigating large codebases without repeating mistakes

## Key Design Decisions

### Structural Representation
- Uses `StructuralRep` newtype wrapping a String (placeholder for actual AST snippets from tree-sitter)
- In a full implementation, this would be replaced with proper AST representations
- Provides Hashable instance for efficient lookup in evidence store

### Failure Modeling
- `FailureReason` GADT captures different failure modes (TypeError, Divergence, MissingInstance, OtherReason)
- Extensible for new failure types as needed

### Evidence Storage
- `EvidenceStore` uses HashMap for O(1) lookup of known failures
- Semigroup and Monoid instances allow combining evidence from different experiments
- Evidence is keyed by structural representation to detect equivalent failed changes

### Institution Integration
- Evidence is indexed by signature (via `Proxy sig`) to maintain institution-specific context
- `proposeChange` and `recordFailure` functions integrate evidence checking into institution workflows
- Typeclass `ToStructuralRep` allows different change representations to be converted to structural form

## Current Limitations
- Structural representation is currently String-based (should be replaced with tree-sitter AST snippets)
- No actual similarity checking (only exact structural rep matches) - should integrate tree-diff for structural similarity
- No persistence mechanism (evidence is lost between runs) - could be saved to disk or database

## Conformance to Requirements
- ✅ Provides evidence preservation mechanism for autonomous coding
- ✅ Supports structural counterexample tracking
- ✅ Integrates with existing Institution framework
- ✅ Written in Haskell with appropriate extensions
- ✅ Builds and tests successfully with the rest of the project

## Future Work
1. Replace String-based StructuralRep with actual tree-sitter AST snippets
2. Integrate tree-diff for structural similarity checking (not just exact matches)
3. Add persistence layer to save/load evidence stores between sessions
4. Connect to actual build/test sandbox to automatically record failures
5. Integrate with CEGIS framework for guided synthesis using evidence
