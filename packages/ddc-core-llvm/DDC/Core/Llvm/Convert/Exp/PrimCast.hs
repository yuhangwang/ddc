
module DDC.Core.Llvm.Convert.Exp.PrimCast
        (convPrimCast)
where
import DDC.Llvm.Syntax
import DDC.Core.Llvm.Convert.Exp.Atom
import DDC.Core.Llvm.Convert.Type
import DDC.Core.Llvm.Convert.Context
import DDC.Core.Llvm.Convert.Base
import DDC.Core.Salt.Platform
import DDC.Core.Compounds
import Data.Sequence                    (Seq)
import qualified DDC.Core.Exp           as C
import qualified DDC.Core.Salt          as A
import qualified Data.Sequence          as Seq
import qualified Data.Map               as Map


-- | Convert a primitive call to LLVM,
--   or Nothing if this doesn't look like such an operation.
convPrimCast
        :: Show a
        => Context              -- ^ Context of the conversion.
        -> Maybe Var            -- ^ Assign result to this var.
        -> A.PrimOp             -- ^ Primitive to call.
        -> C.Type A.Name        -- ^ Type of the primitive.
        -> [C.Exp a A.Name]     -- ^ Arguments to primitive.
        -> Maybe (ConvertM (Seq AnnotInstr))

convPrimCast ctx mdst p _tPrim xs
 = case p of
        A.PrimCast A.PrimCastConvert
         | [C.XType _ tDst, C.XType _ tSrc, xSrc] <- xs
         , Just vDst            <- mdst
         -> Just $ do
                instr   <- convPrimConvert ctx tDst vDst tSrc xSrc
                return  $  Seq.singleton (annotNil instr)

        A.PrimCast A.PrimCastPromote
         | [C.XType _ tDst, C.XType _ tSrc, xSrc] <- xs
         , Just vDst            <- mdst
         , Just mSrc            <- mconvAtom ctx xSrc
         -> Just $ do
                xSrc'   <- mSrc
                instr   <- convPrimPromote ctx tDst vDst tSrc xSrc'
                return  $  Seq.singleton (annotNil instr) 

        A.PrimCast A.PrimCastTruncate
         | [C.XType _ tDst, C.XType _ tSrc, xSrc] <- xs
         , Just vDst            <- mdst
         , Just mSrc            <- mconvAtom ctx xSrc
         -> Just $ do
                xSrc'   <- mSrc
                instr   <- convPrimTruncate ctx tDst vDst tSrc xSrc'
                return  $  Seq.singleton (annotNil instr)

        _ -> Nothing


-- | Convert a primitive conversion operator to LLVM,
--   or `Nothing` for an invalid conversion.
convPrimConvert
        :: Context
        -> C.Type A.Name -> Var
        -> C.Type A.Name -> C.Exp a A.Name
        -> ConvertM Instr

convPrimConvert ctx tDst vDst tSrc xSrc
 | pp     <- contextPlatform ctx
 , kenv   <- contextKindEnv  ctx
 = do
        tSrc'   <- convertType pp kenv tSrc
        tDst'   <- convertType pp kenv tDst

        case tSrc' of

         -- Produce the code pointer for a top-level super.
         TPointer TFunction{}

          -- Argument is the name of the super itself.
          | tDst'      == TInt (8 * platformAddrBytes pp)
          , Just mSrc               <- mconvAtom ctx xSrc
          -> do xSrc' <- mSrc
                return $ IConv vDst ConvPtrtoint xSrc'

          -- Argument is a variable that has been bound to an application of
          -- a super variable to some type arguments.
          | tDst'      == TInt (8 * platformAddrBytes pp)
          , C.XVar a (C.UName nVar) <- xSrc
          , Just (nSuper, _tsArgs)  <- Map.lookup nVar (contextSuperBinds ctx)
          , Just mSrc               <- mconvAtom ctx (C.XVar a (C.UName nSuper))
          -> do xSrc' <- mSrc
                return $ IConv vDst ConvPtrtoint xSrc'

         _ -> throw $ "invalid conversion"


-- | Convert a primitive promotion operator to LLVM,
--   or `Nothing` for an invalid promotion.
convPrimPromote
        :: Context
        -> C.Type A.Name -> Var
        -> C.Type A.Name -> Exp
        -> ConvertM Instr

convPrimPromote ctx tDst vDst tSrc xSrc
 | pp    <- contextPlatform ctx
 , kenv  <- contextKindEnv  ctx
 , Just (A.NamePrimTyCon tcSrc, _) <- takePrimTyConApps tSrc
 , Just (A.NamePrimTyCon tcDst, _) <- takePrimTyConApps tDst
 , A.primCastPromoteIsValid pp tcSrc tcDst
 = do
        tSrc' <- convertType pp kenv tSrc
        tDst' <- convertType pp kenv tDst

        case (tDst', tSrc') of
         (TInt bitsDst, TInt bitsSrc)

          -- Same sized integers
          | bitsDst == bitsSrc
          -> return $ ISet vDst xSrc

          -- Both Unsigned
          | isUnsignedT tSrc, isUnsignedT tDst
          , bitsDst > bitsSrc
          -> return $ IConv vDst ConvZext xSrc

          -- Both Signed
          | isSignedT tSrc,   isSignedT tDst
          , bitsDst > bitsSrc
          -> return $ IConv vDst ConvSext xSrc

          -- Unsigned to Signed
          | isUnsignedT tSrc, isSignedT   tDst
          , bitsDst > bitsSrc
          -> return $ IConv vDst ConvZext xSrc

         -- This was supposed to be a valid promotion
         _ -> error "ddc-core-llvm.convertPrimPromote: cannot convert"

 | otherwise 
 = throw "invalid promotion"


-- | Convert a primitive truncation to LLVM,
--   or `Nothing` for an invalid truncation.
convPrimTruncate
        :: Context
        -> C.Type  A.Name -> Var
        -> C.Type  A.Name -> Exp
        -> ConvertM Instr

convPrimTruncate ctx tDst vDst tSrc xSrc
 | pp    <- contextPlatform ctx
 , kenv  <- contextKindEnv  ctx
 , Just (A.NamePrimTyCon tcSrc, _) <- takePrimTyConApps tSrc
 , Just (A.NamePrimTyCon tcDst, _) <- takePrimTyConApps tDst
 , A.primCastTruncateIsValid pp tcSrc tcDst
 = do
        tSrc' <- convertType pp kenv tSrc
        tDst' <- convertType pp kenv tDst

        case (tDst', tSrc') of
         (TInt bitsDst, TInt bitsSrc)
          -- Same sized integers
          | bitsDst == bitsSrc
          -> return $ ISet vDst xSrc

          -- Destination is smaller
          | bitsDst < bitsSrc
          -> return $ IConv vDst ConvTrunc xSrc

          -- Unsigned to Signed,
          --  destination is larger
          | bitsDst > bitsSrc
          , isUnsignedT tSrc,   isSignedT tDst
          -> return$ IConv vDst ConvZext xSrc

         -- This was supposed to be a valid truncation.
         _ -> error "ddc-core-llvm.convPrimTruncate: cannot convert"

 | otherwise 
 = throw "invalid truncation"
