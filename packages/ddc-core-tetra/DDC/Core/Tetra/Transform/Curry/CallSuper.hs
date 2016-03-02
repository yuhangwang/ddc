
module DDC.Core.Tetra.Transform.Curry.CallSuper
        ( makeCallSuperSaturated
        , makeCallSuperUnder)
where
import DDC.Core.Tetra.Transform.Curry.Interface
import DDC.Core.Tetra
import DDC.Core.Exp
import qualified DDC.Type.Transform.Instantiate as T
import qualified DDC.Core.Tetra.Compounds       as C
import qualified DDC.Core.Call                  as Call


---------------------------------------------------------------------------------------------------
-- | Fully saturated application.
--
--   When the eliminators at the call site exactly match the way the super
--   is constructed then we can call the super directly. In the generated
--   object code we do a standard function call.
--
makeCallSuperSaturated
        :: n                    -- ^ Name of super to call.
        -> [Call.Cons n]        -- ^ How the super is constructed.
        -> [Call.Elim () n]     -- ^ Eliminators at call site.
        -> Maybe (Exp () n)

makeCallSuperSaturated nF cs es
 | length es == length cs
 , and  $ zipWith Call.elimForCons es cs
 = Just $ foldl Call.applyElim (XVar () (UName nF)) es

 | otherwise     
 = Nothing


---------------------------------------------------------------------------------------------------
-- | Under saturated application.
--
--   When we don't have enough eliminators to match all the constructors
--   in the function header then the application is under-saturated.
--
--   We build a PAP object to store the arguments we have at the moment,
--   and the runtime will wait until we have the full set until calling
--   the underlying super.
--
--   This only works for supers in the standard form,
--    eg /\(a1 : k1). .. /\(a2 : k1). \(x1 : t1). .. \(x2 : t2). box
--
--   At the call site we must provide type arguments to satify
--   all the type parameters, but don't need to supply all the value
--   arguments, or to run the box. We restrict the call pattern this
--   way to make the runtime easier to write, and so that we can implement
--   PAP construction and elimination using primitives with straightforward
--   types. 
--
makeCallSuperUnder
        :: Name                 -- ^ Name of super to call.
        -> Type Name            -- ^ Type of super.
        -> [Call.Cons Name]     -- ^ How the super is constructed.
        -> [Call.Elim () Name]  -- ^ Eliminators at call site.
        -> Maybe (Exp () Name)

makeCallSuperUnder nF tF cs es
 -- We have more constructors than eliminators.
 | length es <  length cs

 -- The super and call  must be in standard form.
 , Just (esType, esValue,  esRuns) <- Call.splitStdCallElims es
 , Just (csType, _csValue, _cBox)  <- Call.splitStdCallCons  cs

 -- There must be types to satisfy all of the type parameters of the super.
 , length esType == length csType

 = let
        -- Split the quantifiers, parameter type, and body type
        -- from the type of the super.
        Just tF_inst        = T.instantiateTs tF [t | Call.ElimType _ _ t <- esType]
        (tsParam,  tResult) = C.takeTFunArgResult tF_inst
        iArity              = length cs

        xsArgType       = [XType at t  | Call.ElimType  _ at t  <- esType]
        xsArgValue      = [x           | Call.ElimValue _ x     <- esValue]

        -- Split the value parameters into ones accepted by the super,
        -- and ones that are accepted by the returned closures.
        (tsParamLam, tsParamClo) = splitAt iArity tsParam
        
        -- Build the type of the returned value.
        Just tResult'   = C.tFunOfList (tsParamClo ++ [tResult])
        
        -- Instantiate all the type parameters.
        xFunAPP         = (C.xApps () (XVar () (UName nF)) xsArgType)

        -- Split types of the super parameters into the ones that can be
        -- satisfied by this application, and the remaining parameters that
        -- are still waiting for arguments.
        (tsParamSat, tsParamRemain)     
                        = splitAt (length xsArgValue) tsParamLam

        -- The type of the result after performing this application.
        -- If there are remaining, un-saturated parameters the result
        -- type will still be a function.
        Just tResultClo = C.tFunOfList (tsParamRemain ++ [tResult'])

        tParamFirst : tsParamRest = tsParamLam
        Just tSuperResult = C.tFunOfList (tsParamRest ++   [tResult'])

   in Just
        $ makeRuns () (length esRuns)
        $ C.xApps  () (C.xFunCurry () tsParamSat tResultClo 
                       (C.xFunCReify () tParamFirst tSuperResult xFunAPP))
              xsArgValue

 | otherwise
 = Nothing

