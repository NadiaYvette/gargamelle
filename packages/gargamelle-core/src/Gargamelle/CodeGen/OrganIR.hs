{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gargamelle.CodeGen.OrganIR
  ( -- * 1. Polytropos & Penelope Static Layout Descriptors
    SlotIndex (..)
  , RowLayoutDescriptor (..)
  , ResumptionKind (..)
  , EffectVectorDescriptor (..)
  , buildRowLayoutDescriptor
  , buildEffectVectorDescriptor
  , resolveRowSlot
    -- * 2. OrganIR Core AST & SSA Representation
  , SSAVal (..)
  , OrganType (..)
  , OrganPrimOp (..)
  , OrganRhs (..)
  , OrganStmt (..)
  , OrganProc (..)
    -- * 3. Lowering Verified SynTerm & LiquidSig to OrganIR
  , lowerStalkToOrganProc
  , lowerLiquidSort
    -- * 4. Target Emitters: MLIR (`organ` + `scf` + `llvm`) & GCC GIMPLE SSA
  , emitMLIRProc
  , emitGimpleProc
  ) where

import Control.Monad (foldM)
import Control.Monad.Reader (MonadReader (..), ReaderT (..), asks, local)
import Control.Monad.State.Strict (MonadState (..), StateT (..), gets, modify', runStateT)
import Data.Functor.Identity (Identity (..))
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
  ( BinOp (..)
  , LiquidPred (..)
  , LiquidSig (..)
  , LiquidSort (..)
  , RBase (..)
  , RType (..)
  , RelOp (..)
  , SymName
  , SynTerm (..)
  )
import Gargamelle.Core.Institution.Liquid.Penelope (EffectRow (..))
import Gargamelle.Core.Institution.Liquid.Polytropos (OpenRow (..))

--------------------------------------------------------------------------------
-- 1. Polytropos & Penelope Static Layout Descriptors
--------------------------------------------------------------------------------

data SlotIndex
  = StaticSlot !Int
  | OpenTailSlot SymName SymName
  deriving stock (Eq, Show, Generic)

data RowLayoutDescriptor = RowLayoutDescriptor
  { rldKnownSlots :: Map SymName Int
  , rldKnownSorts :: Map SymName LiquidSort
  , rldOpenTail   :: Maybe SymName
  } deriving stock (Eq, Show, Generic)

data ResumptionKind
  = TailResumptive
  | DelimitedOneShot
  deriving stock (Eq, Show, Generic)

data EffectVectorDescriptor = EffectVectorDescriptor
  { evdSlotMap  :: Map SymName (Int, ResumptionKind)
  , evdOpenTail :: Maybe SymName
  } deriving stock (Eq, Show, Generic)

buildRowLayoutDescriptor :: OpenRow -> RowLayoutDescriptor
buildRowLayoutDescriptor OpenRow{..} =
  let sortedFields = sort (Map.keys rowFields)
      slotIndices = Map.fromList (zip sortedFields [0..])
  in RowLayoutDescriptor
       { rldKnownSlots = slotIndices
       , rldKnownSorts = rowFields
       , rldOpenTail   = rowTail
       }

buildEffectVectorDescriptor :: (SymName -> ResumptionKind) -> EffectRow -> EffectVectorDescriptor
buildEffectVectorDescriptor resumeKindFn EffectRow{..} =
  let slotMap = Map.fromList [ (eff, (idx, resumeKindFn eff)) | (idx, eff) <- zip [0..] effList ]
  in EffectVectorDescriptor
       { evdSlotMap  = slotMap
       , evdOpenTail = effTail
       }

resolveRowSlot :: RowLayoutDescriptor -> SymName -> SlotIndex
resolveRowSlot RowLayoutDescriptor{..} lbl =
  case Map.lookup lbl rldKnownSlots of
    Just idx -> StaticSlot idx
    Nothing  -> case rldOpenTail of
      Just tailVar -> OpenTailSlot tailVar lbl
      Nothing      -> StaticSlot 0

--------------------------------------------------------------------------------
-- 2. OrganIR Core AST & SSA Representation
--------------------------------------------------------------------------------

newtype SSAVal = SSAVal { unSSAVal :: Text }
  deriving stock (Eq, Ord, Show, Generic)

data OrganType
  = OTInt64
  | OTBool
  | OTPolytroposRep !Int
  | OTEffectVec !Int
  | OTOpaquePtr
  deriving stock (Eq, Ord, Show, Generic)

data OrganPrimOp
  = OpAdd
  | OpSub
  | OpMul
  | OpEq
  | OpNeq
  | OpLt
  | OpLe
  | OpGt
  | OpGe
  | OpAnd
  | OpOr
  deriving stock (Eq, Show, Generic)

data OrganRhs
  = RhsConstInt !Integer
  | RhsConstBool !Bool
  | RhsCopy SSAVal
  | RhsPrimOp OrganPrimOp SSAVal SSAVal
  | RhsUnaryNot SSAVal
  -- Polytropos RecordF / VariantF Unified `Rep` Primitives:
  | RhsRepSlotLoad SSAVal SlotIndex SymName
  | RhsRepSlotUpdate SSAVal SlotIndex SymName SSAVal
  | RhsVariantTagEq SSAVal SlotIndex SymName
  | RhsVariantPayload SSAVal SlotIndex SymName
  | RhsVariantMake SlotIndex SymName SSAVal
  -- Penelope Algebraic Effect Primitives:
  | RhsEffectPerform SymName !Int ResumptionKind SSAVal SSAVal
  | RhsExternalCall SymName [SSAVal]
  deriving stock (Eq, Show, Generic)

data OrganStmt
  = StmtAssign SSAVal OrganType OrganRhs
  | StmtAssume SSAVal Text
  | StmtIf
      { ifCondVal  :: SSAVal
      , ifResult   :: SSAVal
      , ifResType  :: OrganType
      , ifThenBody :: [OrganStmt]
      , ifThenRet  :: SSAVal
      , ifElseBody :: [OrganStmt]
      , ifElseRet  :: SSAVal
      }
  | StmtUnreachable Text
  | StmtReturn SSAVal OrganType
  deriving stock (Eq, Show, Generic)

data OrganProc = OrganProc
  { procName       :: SymName
  , procParams     :: [(SSAVal, OrganType)]
  , procReturnType :: OrganType
  , procBody       :: [OrganStmt]
  } deriving stock (Eq, Show, Generic)

--------------------------------------------------------------------------------
-- 3. SSA Lowering Monad: `SynTerm` + `LiquidSig` -> `OrganProc`
--------------------------------------------------------------------------------

data LowerEnv = LowerEnv
  { leRowLayout   :: RowLayoutDescriptor
  , leEffLayout   :: EffectVectorDescriptor
  , leVarBindings :: Map SymName (SSAVal, OrganType)
  , leEffVecParam :: SSAVal
  }

data LowerState = LowerState
  { lsNextTempId :: !Int
  , lsStmtsRev   :: [OrganStmt]
  }

newtype OrganLowerM a = OrganLowerM
  { unOrganLowerM :: ReaderT LowerEnv (StateT LowerState Identity) a
  } deriving newtype (Functor, Applicative, Monad, MonadReader LowerEnv, MonadState LowerState)

freshSSA :: Text -> OrganLowerM SSAVal
freshSSA prefix = do
  n <- gets lsNextTempId
  modify' $ \s -> s { lsNextTempId = n + 1 }
  pure $ SSAVal (prefix <> "_" <> T.pack (show n))

emitStmt :: OrganStmt -> OrganLowerM ()
emitStmt stmt = modify' $ \s -> s { lsStmtsRev = stmt : lsStmtsRev s }

emitAssign :: Text -> OrganType -> OrganRhs -> OrganLowerM SSAVal
emitAssign prefix ty rhs = do
  dst <- freshSSA prefix
  emitStmt (StmtAssign dst ty rhs)
  pure dst

captureBranchStmts :: OrganLowerM a -> OrganLowerM (a, [OrganStmt])
captureBranchStmts action = do
  oldRev <- gets lsStmtsRev
  modify' $ \s -> s { lsStmtsRev = [] }
  res <- action
  branchRev <- gets lsStmtsRev
  modify' $ \s -> s { lsStmtsRev = oldRev }
  pure (res, reverse branchRev)

lowerLiquidSort :: RowLayoutDescriptor -> LiquidSort -> OrganType
lowerLiquidSort rowDesc = \case
  SortInt -> OTInt64
  SortBool -> OTBool
  SortRecordRow _ -> OTPolytroposRep (Map.size (rldKnownSlots rowDesc))
  SortVariantRow _ -> OTPolytroposRep (Map.size (rldKnownSlots rowDesc))
  SortADT n _
    | "RecordF_" `T.isPrefixOf` n || "VariantF_" `T.isPrefixOf` n ->
        OTPolytroposRep (Map.size (rldKnownSlots rowDesc))
    | otherwise -> OTOpaquePtr
  SortEffectRow _ -> OTEffectVec 0
  _ -> OTInt64

lowerStalkToOrganProc
  :: SymName
  -> RowLayoutDescriptor
  -> EffectVectorDescriptor
  -> LiquidSig
  -> RBase
  -> SynTerm
  -> OrganProc
lowerStalkToOrganProc name rowDesc effDesc LiquidSig{..} goalBase rootTerm =
  let effVecVal = SSAVal "eff_vec"
      effVecType = OTEffectVec (Map.size (evdSlotMap effDesc))
      envParams =
        [ (varName, (SSAVal varName, lowerLiquidSort rowDesc sortS))
        | (varName, RBScalar (RBase _ sortS _)) <- Map.toAscList sigEnv
        ]
      paramList = if Map.null (evdSlotMap effDesc) then map snd envParams else (effVecVal, effVecType) : map snd envParams
      retType = lowerLiquidSort rowDesc (rSort goalBase)
      initEnv = LowerEnv
        { leRowLayout   = rowDesc
        , leEffLayout   = effDesc
        , leVarBindings = Map.fromList envParams
        , leEffVecParam = effVecVal
        }
      initState = LowerState 1 []
      (retVal, finalState) = runIdentity $
        runStateT (runReaderT (unOrganLowerM $ do
          mapM_ emitEntryAssumption sigPathCond
          lowerSynTerm retType rootTerm) initEnv) initState
      allStmts = reverse (lsStmtsRev finalState) ++ [StmtReturn retVal retType]
  in OrganProc
       { procName       = name
       , procParams     = paramList
       , procReturnType = retType
       , procBody       = allStmts
       }
  where
    emitEntryAssumption :: LiquidPred -> OrganLowerM ()
    emitEntryAssumption p = do
      condVal <- lowerLiquidPredToSSA p
      emitStmt (StmtAssume condVal (T.pack (show p)))

    lowerSynTerm :: OrganType -> SynTerm -> OrganLowerM SSAVal
    lowerSynTerm expectedType = \case
      TVar v -> do
        bindings <- asks leVarBindings
        case Map.lookup v bindings of
          Just (ssa, _ty) -> pure ssa
          Nothing         -> pure (SSAVal v)
      TIntLit i ->
        emitAssign "c_int" OTInt64 (RhsConstInt i)
      TBoolLit b ->
        emitAssign "c_bool" OTBool (RhsConstBool b)
      TLam x body -> do
        let paramSSA = SSAVal x
        local (\e -> e { leVarBindings = Map.insert x (paramSSA, OTInt64) (leVarBindings e) }) $
          lowerSynTerm expectedType body
      TEffPure inner ->
        lowerSynTerm expectedType inner
      TEffBind nextStSym opTerm contTerm -> do
        opResVal <- lowerSynTerm expectedType opTerm
        local (\e -> e { leVarBindings = Map.insert nextStSym (opResVal, expectedType) (leVarBindings e) }) $
          lowerSynTerm expectedType contTerm
      TIf guardPred thenBranch elseBranch -> do
        condSSA <- lowerLiquidPredToSSA guardPred
        ((thenRet, thenStmts), (elseRet, elseStmts)) <- do
          tBranch <- captureBranchStmts (lowerSynTerm expectedType thenBranch)
          eBranch <- captureBranchStmts (lowerSynTerm expectedType elseBranch)
          pure (tBranch, eBranch)
        phiOut <- freshSSA "phi_if"
        emitStmt StmtIf
          { ifCondVal  = condSSA
          , ifResult   = phiOut
          , ifResType  = expectedType
          , ifThenBody = thenStmts
          , ifThenRet  = thenRet
          , ifElseBody = elseStmts
          , ifElseRet  = elseRet
          }
        pure phiOut
      TApp (TVar fn) args
        -- 1. Statically Verified Variant Exhaustion: `absurdVariantF u`
        | fn == "absurdVariantF" -> do
            emitStmt (StmtUnreachable "verified_empty_vtags_by_LiquidInstitution")
            emitAssign "dead_val" expectedType (RhsConstInt 0)
        -- 2. Polytropos RecordF Field Projection: `getF_<l> r`
        | "getF_" `T.isPrefixOf` fn, [recTerm] <- args -> do
            let lbl = T.drop 5 fn
            rDesc <- asks leRowLayout
            recSSA <- lowerSynTerm (OTPolytroposRep (Map.size (rldKnownSlots rDesc))) recTerm
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("fld_" <> lbl) OTInt64 (RhsRepSlotLoad recSSA slotIdx lbl)
        -- 3. Polytropos RecordF Field Update: `setF_<l> val r`
        | "setF_" `T.isPrefixOf` fn, [valTerm, recTerm] <- args -> do
            let lbl = T.drop 5 fn
            rDesc <- asks leRowLayout
            let repTy = OTPolytroposRep (Map.size (rldKnownSlots rDesc))
            valSSA <- lowerSynTerm OTInt64 valTerm
            recSSA <- lowerSynTerm repTy recTerm
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("rep_upd_" <> lbl) repTy (RhsRepSlotUpdate recSSA slotIdx lbl valSSA)
        -- 4. Polytropos VariantF Payload Extraction: `matchTagF_<l> u`
        | "matchTagF_" `T.isPrefixOf` fn, [varTerm] <- args -> do
            let lbl = T.drop 10 fn
            rDesc <- asks leRowLayout
            let repTy = OTPolytroposRep (Map.size (rldKnownSlots rDesc))
            varSSA <- lowerSynTerm repTy varTerm
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("vpay_" <> lbl) OTInt64 (RhsVariantPayload varSSA slotIdx lbl)
        -- 5. Polytropos VariantF Injection: `injF_<l> x`
        | "injF_" `T.isPrefixOf` fn, [payTerm] <- args -> do
            let lbl = T.drop 5 fn
            rDesc <- asks leRowLayout
            let repTy = OTPolytroposRep (Map.size (rldKnownSlots rDesc))
            paySSA <- lowerSynTerm OTInt64 payTerm
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("vinj_" <> lbl) repTy (RhsVariantMake slotIdx lbl paySSA)
        -- 6. Penelope Vector-Dispatched Effect Operation: `perform_<E> arg`
        | "perform_" `T.isPrefixOf` fn, [argTerm] <- args -> do
            let effName = T.drop 8 fn
            eDesc <- asks leEffLayout
            effVecSSA <- asks leEffVecParam
            argSSA <- lowerSynTerm expectedType argTerm
            let (slotIdx, resumeKind) =
                  Map.findWithDefault (0, TailResumptive) effName (evdSlotMap eDesc)
            emitAssign ("eff_" <> effName) expectedType $
              RhsEffectPerform effName slotIdx resumeKind effVecSSA argSSA
        -- 7. Builtin Binary Arithmetic Primitives
        | fn == "add", [a, b] <- args -> do
            va <- lowerSynTerm OTInt64 a
            vb <- lowerSynTerm OTInt64 b
            emitAssign "sum" OTInt64 (RhsPrimOp OpAdd va vb)
        | fn == "sub", [a, b] <- args -> do
            va <- lowerSynTerm OTInt64 a
            vb <- lowerSynTerm OTInt64 b
            emitAssign "diff" OTInt64 (RhsPrimOp OpSub va vb)
        -- 8. Crystallized Combinator or External Call
        | otherwise -> do
            argSSAs <- mapM (lowerSynTerm expectedType) args
            emitAssign ("call_" <> fn) expectedType (RhsExternalCall fn argSSAs)
      TApp hd args -> do
        hdSSA <- lowerSynTerm expectedType hd
        argSSAs <- mapM (lowerSynTerm expectedType) args
        emitAssign "app" expectedType (RhsExternalCall (unSSAVal hdSSA) argSSAs)

    lowerLiquidPredToSSA :: LiquidPred -> OrganLowerM SSAVal
    lowerLiquidPredToSSA = \case
      PTrue ->
        emitAssign "b_true" OTBool (RhsConstBool True)
      PFalse ->
        emitAssign "b_false" OTBool (RhsConstBool False)
      PVar v ->
        lowerSynTerm OTInt64 (TVar v)
      PIntLit i ->
        emitAssign "c_i" OTInt64 (RhsConstInt i)
      PMeasureApp m e
        | "sel_" `T.isPrefixOf` m -> do
            let lbl = T.drop 4 m
            rDesc <- asks leRowLayout
            recSSA <- lowerLiquidPredToSSA e
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("sel_" <> lbl) OTInt64 (RhsRepSlotLoad recSSA slotIdx lbl)
        | "vpayload_" `T.isPrefixOf` m -> do
            let lbl = T.drop 9 m
            rDesc <- asks leRowLayout
            varSSA <- lowerLiquidPredToSSA e
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("vpay_" <> lbl) OTInt64 (RhsVariantPayload varSSA slotIdx lbl)
        | otherwise -> do
            argSSA <- lowerLiquidPredToSSA e
            emitAssign ("meas_" <> m) OTInt64 (RhsExternalCall m [argSSA])
      PRel SetMember (PVar tagSym) (PMeasureApp "vtags" varExpr)
        | "Tag_" `T.isPrefixOf` tagSym -> do
            let lbl = T.drop 4 tagSym
            rDesc <- asks leRowLayout
            varSSA <- lowerLiquidPredToSSA varExpr
            let slotIdx = resolveRowSlot rDesc lbl
            emitAssign ("is_tag_" <> lbl) OTBool (RhsVariantTagEq varSSA slotIdx lbl)
      PRel op l r -> do
        vl <- lowerLiquidPredToSSA l
        vr <- lowerLiquidPredToSSA r
        let primOp = case op of
              Eq  -> OpEq
              Neq -> OpNeq
              Lt  -> OpLt
              Le  -> OpLe
              Gt  -> OpGt
              Ge  -> OpGe
              _   -> OpEq
        emitAssign "cmp" OTBool (RhsPrimOp primOp vl vr)
      PBinOp op l r -> do
        vl <- lowerLiquidPredToSSA l
        vr <- lowerLiquidPredToSSA r
        let primOp = case op of
              Add -> OpAdd
              Sub -> OpSub
              Mul -> OpMul
              _   -> OpAdd
        emitAssign "arith" OTInt64 (RhsPrimOp primOp vl vr)
      PNot inner -> do
        v <- lowerLiquidPredToSSA inner
        emitAssign "not" OTBool (RhsUnaryNot v)
      PAnd [] ->
        emitAssign "b_true" OTBool (RhsConstBool True)
      PAnd (p:ps) -> do
        v0 <- lowerLiquidPredToSSA p
        foldM (\acc nxt -> do
          vn <- lowerLiquidPredToSSA nxt
          emitAssign "and" OTBool (RhsPrimOp OpAnd acc vn)) v0 ps
      POr [] ->
        emitAssign "b_false" OTBool (RhsConstBool False)
      POr (p:ps) -> do
        v0 <- lowerLiquidPredToSSA p
        foldM (\acc nxt -> do
          vn <- lowerLiquidPredToSSA nxt
          emitAssign "or" OTBool (RhsPrimOp OpOr acc vn)) v0 ps
      _ ->
        emitAssign "b_true" OTBool (RhsConstBool True)

--------------------------------------------------------------------------------
-- 4. Target Emitter A: MLIR (`organ` + `scf` + `arith` + `llvm`)
--------------------------------------------------------------------------------

emitMLIRProc :: OrganProc -> Text
emitMLIRProc OrganProc{..} =
  let renderedParams = T.intercalate ", "
        [ "%" <> unSSAVal v <> ": " <> renderMLIRType ty
        | (v, ty) <- procParams
        ]
      retTyText = renderMLIRType procReturnType
      bodyLines = concatMap (emitMLIRStmt "  ") procBody
  in T.unlines $
       [ "func.func @" <> procName <> "(" <> renderedParams <> ") -> " <> retTyText <> " {" ]
       ++ bodyLines
       ++ [ "}" ]

renderMLIRType :: OrganType -> Text
renderMLIRType = \case
  OTInt64           -> "i64"
  OTBool            -> "i1"
  OTPolytroposRep n -> "!organ.rep<" <> T.pack (show n) <> ">"
  OTEffectVec m     -> "!organ.eff_vec<" <> T.pack (show m) <> ">"
  OTOpaquePtr       -> "!llvm.ptr"

emitMLIRStmt :: Text -> OrganStmt -> [Text]
emitMLIRStmt indent = \case
  StmtAssign dst ty rhs ->
    [ indent <> "%" <> unSSAVal dst <> " = " <> emitMLIRRhs ty rhs ]
  StmtAssume condVal comment ->
    [ indent <> "// Verified Liquid Refinement: " <> comment
    , indent <> "llvm.intr.assume %" <> unSSAVal condVal <> " : i1"
    ]
  StmtUnreachable reason ->
    [ indent <> "// Statically unreachable (" <> reason <> ")"
    , indent <> "llvm.unreachable"
    ]
  StmtReturn retVal retTy ->
    [ indent <> "func.return %" <> unSSAVal retVal <> " : " <> renderMLIRType retTy ]
  StmtIf{..} ->
    let tyTxt = renderMLIRType ifResType
        thenLines = concatMap (emitMLIRStmt (indent <> "  ")) ifThenBody
        elseLines = concatMap (emitMLIRStmt (indent <> "  ")) ifElseBody
    in [ indent <> "%" <> unSSAVal ifResult <> " = scf.if %" <> unSSAVal ifCondVal <> " -> (" <> tyTxt <> ") {" ]
       ++ thenLines
       ++ [ indent <> "  scf.yield %" <> unSSAVal ifThenRet <> " : " <> tyTxt
          , indent <> "} else {"
          ]
       ++ elseLines
       ++ [ indent <> "  scf.yield %" <> unSSAVal ifElseRet <> " : " <> tyTxt
          , indent <> "}"
          ]

emitMLIRRhs :: OrganType -> OrganRhs -> Text
emitMLIRRhs ty = \case
  RhsConstInt i ->
    "arith.constant " <> T.pack (show i) <> " : i64"
  RhsConstBool True ->
    "arith.constant true"
  RhsConstBool False ->
    "arith.constant false"
  RhsCopy src ->
    "organ.copy %" <> unSSAVal src <> " : " <> renderMLIRType ty
  RhsUnaryNot src ->
    "arith.xori %" <> unSSAVal src <> ", true : i1"
  RhsPrimOp op l r ->
    let mlirOp = case op of
          OpAdd -> "arith.addi"
          OpSub -> "arith.subi"
          OpMul -> "arith.muli"
          OpEq  -> "arith.cmpi eq,"
          OpNeq -> "arith.cmpi ne,"
          OpLt  -> "arith.cmpi slt,"
          OpLe  -> "arith.cmpi sle,"
          OpGt  -> "arith.cmpi sgt,"
          OpGe  -> "arith.cmpi sge,"
          OpAnd -> "arith.andi"
          OpOr  -> "arith.ori"
        opTy = if op `elem` [OpAdd, OpSub, OpMul] then "i64" else "i1"
    in mlirOp <> " %" <> unSSAVal l <> ", %" <> unSSAVal r <> " : " <> opTy
  RhsRepSlotLoad recVal slotIdx lbl ->
    "organ.rep.slot_load %" <> unSSAVal recVal <> "[" <> renderSlotAttr slotIdx <> "] {field = \"" <> lbl <> "\"} : i64"
  RhsRepSlotUpdate recVal slotIdx lbl newVal ->
    "organ.rep.slot_update %" <> unSSAVal recVal <> "[" <> renderSlotAttr slotIdx <> "], %" <> unSSAVal newVal
    <> " {field = \"" <> lbl <> "\"} : " <> renderMLIRType ty
  RhsVariantTagEq varVal slotIdx lbl ->
    "organ.rep.tag_eq %" <> unSSAVal varVal <> ", " <> renderSlotAttr slotIdx <> " {tag = \"" <> lbl <> "\"} : i1"
  RhsVariantPayload varVal slotIdx lbl ->
    "organ.rep.payload_unchecked %" <> unSSAVal varVal <> "[" <> renderSlotAttr slotIdx <> "] {tag = \"" <> lbl <> "\"} : i64"
  RhsVariantMake slotIdx lbl payVal ->
    "organ.rep.variant_pack " <> renderSlotAttr slotIdx <> ", %" <> unSSAVal payVal
    <> " {tag = \"" <> lbl <> "\"} : " <> renderMLIRType ty
  RhsEffectPerform effName slotIdx resumeKind effVec argVal ->
    let modeAttr = case resumeKind of
          TailResumptive   -> "#organ.tail_resumptive"
          DelimitedOneShot -> "#organ.delimited_oneshot"
    in "organ.eff.perform @" <> effName <> "(%" <> unSSAVal effVec <> "[" <> T.pack (show slotIdx) <> "], %" <> unSSAVal argVal
       <> ") {resumption = " <> modeAttr <> "} : " <> renderMLIRType ty
  RhsExternalCall fn args ->
    let argList = T.intercalate ", " [ "%" <> unSSAVal a | a <- args ]
    in "func.call @" <> fn <> "(" <> argList <> ") : () -> " <> renderMLIRType ty

renderSlotAttr :: SlotIndex -> Text
renderSlotAttr = \case
  StaticSlot i         -> T.pack (show i)
  OpenTailSlot rho lbl -> "sym_offset(@" <> rho <> ", \"" <> lbl <> "\")"

--------------------------------------------------------------------------------
-- 5. Target Emitter B: GCC GIMPLE SSA (`-fgimple`)
--------------------------------------------------------------------------------

emitGimpleProc :: OrganProc -> Text
emitGimpleProc OrganProc{..} =
  let cParams = T.intercalate ", "
        [ renderGimpleType ty <> " " <> unSSAVal v
        | (v, ty) <- procParams
        ]
      retTy = renderGimpleType procReturnType
      (_, bbLines) = emitGimpleBlocks 2 "entry" procBody
  in T.unlines $
       [ retTy <> " __GIMPLE (ssa)"
       , procName <> " (" <> cParams <> ")"
       , "{"
       , "  __BB(2):"
       ]
       ++ bbLines
       ++ [ "}" ]

renderGimpleType :: OrganType -> Text
renderGimpleType = \case
  OTInt64           -> "long int"
  OTBool            -> "_Bool"
  OTPolytroposRep _ -> "struct PolytroposRep *"
  OTEffectVec _     -> "struct PenelopeEffVec *"
  OTOpaquePtr       -> "void *"

emitGimpleBlocks :: Int -> Text -> [OrganStmt] -> (Int, [Text])
emitGimpleBlocks nextBbId _label = go nextBbId []
  where
    go bbId acc [] = (bbId, reverse acc)
    go bbId acc (stmt : rest) = case stmt of
      StmtAssign dst ty rhs ->
        let line = "    " <> renderGimpleType ty <> " " <> unSSAVal dst <> " = " <> emitGimpleRhs rhs <> ";"
        in go bbId (line : acc) rest
      StmtAssume condVal comment ->
        let assumeLine = "    /* Liquid Assume: " <> comment <> " */ if (!" <> unSSAVal condVal <> ") __builtin_unreachable ();"
        in go bbId (assumeLine : acc) rest
      StmtUnreachable reason ->
        let unreachLine = "    /* Unreachable: " <> reason <> " */ __builtin_unreachable ();"
        in go bbId (unreachLine : acc) rest
      StmtReturn retVal _ty ->
        let retLine = "    return " <> unSSAVal retVal <> ";"
        in go bbId (retLine : acc) rest
      StmtIf{..} ->
        let thenBb = bbId + 1
            elseBb = bbId + 2
            mergeBb = bbId + 3
            brHeader =
              [ "    if (" <> unSSAVal ifCondVal <> " != 0)"
              , "      goto __BB" <> T.pack (show thenBb) <> ";"
              , "    else"
              , "      goto __BB" <> T.pack (show elseBb) <> ";"
              , ""
              , "  __BB(" <> T.pack (show thenBb) <> "):"
              ]
            (bbAfterThen, thenLines) = emitGimpleBlocks (mergeBb + 1) "then" ifThenBody
            thenFooter =
              [ "    goto __BB" <> T.pack (show mergeBb) <> ";"
              , ""
              , "  __BB(" <> T.pack (show elseBb) <> "):"
              ]
            (bbAfterElse, elseLines) = emitGimpleBlocks bbAfterThen "else" ifElseBody
            mergeHeader =
              [ "    goto __BB" <> T.pack (show mergeBb) <> ";"
              , ""
              , "  __BB(" <> T.pack (show mergeBb) <> "):"
              , "    " <> renderGimpleType ifResType <> " " <> unSSAVal ifResult
                  <> " = __PHI (__BB" <> T.pack (show thenBb) <> ": " <> unSSAVal ifThenRet
                  <> ", __BB" <> T.pack (show elseBb) <> ": " <> unSSAVal ifElseRet <> ");"
              ]
            combined = reverse acc ++ brHeader ++ thenLines ++ thenFooter ++ elseLines ++ mergeHeader
        in go bbAfterElse (reverse combined) rest

emitGimpleRhs :: OrganRhs -> Text
emitGimpleRhs = \case
  RhsConstInt i ->
    T.pack (show i) <> "l"
  RhsConstBool True ->
    "1"
  RhsConstBool False ->
    "0"
  RhsCopy src ->
    unSSAVal src
  RhsUnaryNot src ->
    "!" <> unSSAVal src
  RhsPrimOp op l r ->
    let cOp = case op of
          OpAdd -> "+"
          OpSub -> "-"
          OpMul -> "*"
          OpEq  -> "=="
          OpNeq -> "!="
          OpLt  -> "<"
          OpLe  -> "<="
          OpGt  -> ">"
          OpGe  -> ">="
          OpAnd -> "&&"
          OpOr  -> "||"
    in unSSAVal l <> " " <> cOp <> " " <> unSSAVal r
  RhsRepSlotLoad recVal slotIdx lbl ->
    unSSAVal recVal <> "->slots[" <> renderGimpleSlot slotIdx <> "] /* ." <> lbl <> " */"
  RhsRepSlotUpdate recVal slotIdx lbl newVal ->
    "__organ_rep_update (" <> unSSAVal recVal <> ", " <> renderGimpleSlot slotIdx
    <> ", " <> unSSAVal newVal <> ") /* ." <> lbl <> " */"
  RhsVariantTagEq varVal slotIdx lbl ->
    "(" <> unSSAVal varVal <> "->tag == " <> renderGimpleSlot slotIdx <> ") /* is_Tag_" <> lbl <> " */"
  RhsVariantPayload varVal _slotIdx lbl ->
    unSSAVal varVal <> "->slots[0] /* unchecked payload " <> lbl <> " */"
  RhsVariantMake slotIdx lbl payVal ->
    "__organ_variant_pack (" <> renderGimpleSlot slotIdx <> ", " <> unSSAVal payVal <> ") /* Tag_" <> lbl <> " */"
  RhsEffectPerform effName slotIdx TailResumptive effVec argVal ->
    unSSAVal effVec <> "->tail_handlers[" <> T.pack (show slotIdx) <> "] ("
    <> unSSAVal effVec <> "->env[" <> T.pack (show slotIdx) <> "], "
    <> unSSAVal argVal <> ") /* tail_resumptive @" <> effName <> " */"
  RhsEffectPerform effName slotIdx DelimitedOneShot effVec argVal ->
    "__organ_yield_oneshot (" <> unSSAVal effVec <> ", " <> T.pack (show slotIdx)
    <> ", " <> unSSAVal argVal <> ") /* delimited @" <> effName <> " */"
  RhsExternalCall fn args ->
    fn <> " (" <> T.intercalate ", " (map unSSAVal args) <> ")"

renderGimpleSlot :: SlotIndex -> Text
renderGimpleSlot = \case
  StaticSlot i         -> T.pack (show i)
  OpenTailSlot rho lbl -> "__ev_offset_" <> rho <> "_" <> lbl
