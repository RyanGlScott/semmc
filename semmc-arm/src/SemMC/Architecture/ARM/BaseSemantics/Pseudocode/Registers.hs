-- | Pseudocode definitions of register management from E1.2.3 (page
-- E1-2294) of the ARMv8 Architecture Reference Manual.

{-# LANGUAGE DataKinds #-}

module SemMC.Architecture.ARM.BaseSemantics.Pseudocode.Registers
    ( aluWritePC
    , loadWritePC
    , branchWritePC
    , bxWritePC
    )
    where

import Data.Maybe
import Prelude hiding ( concat, pred )
import SemMC.Architecture.ARM.BaseSemantics.Base
import SemMC.Architecture.ARM.BaseSemantics.Helpers
import SemMC.Architecture.ARM.BaseSemantics.Pseudocode.ExecState
import SemMC.DSL


-- | ALUWritePC pseudocode.  This is usually for arithmetic operations
-- when they target R15/PC. (E1.2.3, E1-2297)
aluWritePC :: Expr 'TBool -> Expr 'TBV -> SemARM 'Def ()
aluWritePC tgtRegIsPC addr = do
    curarch <- (subArch . fromJust) <$> getArchData
    if curarch == InstrSet_A32
    then bxWritePC tgtRegIsPC addr
    else branchWritePC tgtRegIsPC addr


-- | LoadWritePC pseudocode.  (E1.2.3, E1-2297)
loadWritePC :: Expr 'TBool -> Expr 'TBV -> SemARM 'Def ()
loadWritePC = bxWritePC


-- | BranchWritePC pseudocode.  (E1.2.3, E1-2296)
branchWritePC :: Expr 'TBool -> Expr 'TBV -> SemARM 'Def ()
branchWritePC tgtRegIsPC addr =
    let setAddr curarch = if curarch == InstrSet_A32
                          then bvclr [0,1] addr
                          else bvclr [1] addr
    in updatePC $ \old suba -> "branchWritePC" =: ite tgtRegIsPC (setAddr suba) (old suba)


-- | BxWritePC pseudocode  (E1.2.3, E1-2296)
bxWritePC :: Expr 'TBool -> Expr 'TBV -> SemARM 'Def ()
bxWritePC tgtRegIsPC addr =
    let toT32 = tstBit 0 addr
        setAddr curarch = case curarch of
                            InstrSet_T32EE -> error "TBD: bxWritePC for T32EE mode"
                            InstrSet_Jazelle -> error "TBD: bxWritePC for Jazelle mode"
                            _ -> ite toT32
                                    (bvclr [0] addr)
                                    (ite (andp (tstBit 1 addr) constrainUnpredictable)
                                         (bvclr [1] addr)
                                         addr)
    in do selectInstrSet tgtRegIsPC toT32
          updatePC $ \old suba -> "bxWritePC" =: ite tgtRegIsPC (setAddr suba) (old suba)