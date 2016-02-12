
module DDC.Core.Tetra.Transform.Curry.Interface
        ( FunMap
        , Fun   (..)
        , funMapAddLocalSuper
        , funMapAddForeign

        -- * Utils
        , makeRuns)
where
import DDC.Core.Tetra
import DDC.Core.Tetra.Compounds
import DDC.Core.Module
import DDC.Core.Exp
import Data.Maybe
import Data.Map                                 (Map)
import qualified DDC.Core.Call                  as Call
import qualified Data.Map                       as Map


---------------------------------------------------------------------------------------------------
-- | Map of functional values to their types and arities.
type FunMap
        = Map Name Fun


-- | Enough information about a functional thing to decide how we 
--   should call it. 
data Fun
        -- | A locally defined super.
        --   We can do a saturated call for these directly.
        --   The arity of the super can be determined by inspecting the
        --   definition in the current module.
        = FunLocalSuper
        { _funName      :: Name
        , _funType      :: Type Name 
        , _funCons      :: [Call.Cons Name] }

        -- | An externally defined super.
        --   These are like local supers, except they were compiled
        --   into a separate module.
        | FunExternSuper
        { _funName      :: Name
        , _funType      :: Type Name
        , _funConsMaybe :: Maybe [Call.Cons Name] }

        -- | A foreign imported function.
        --   We can do a saturated call for these directly.
        --   Foreign functions are not represented as closures, 
        --   so we can determine their arity directly from their types.
        | FunForeignSea
        { _funName      :: Name
        , _funType      :: Type Name
        , _funCons      :: [Call.Cons Name] }
        deriving Show


-- | Add the type of this binding to the function map.
funMapAddLocalSuper :: FunMap -> (Bind Name, Exp a Name) -> FunMap
funMapAddLocalSuper funs (b, x)
        | BName n t             <- b
        = let   -- How the super is constructed.
                cons       = Call.takeCallCons x

          in    Map.insert n (FunLocalSuper n t cons) funs

        | otherwise
        = funs


-- | Add the type of a foreign import to the function map.
funMapAddForeign :: FunMap -> (Name, ImportValue Name) -> FunMap
funMapAddForeign funs (n, is)

        -- Imported value where we don't have any arity information.
        --   We allow the function type to be imported, but we won't be able
        --   to call it in the current module without the arity information.
        | ImportValueModule _mn n' tVal Nothing  <- is
        = Map.insert n (FunExternSuper n' tVal Nothing) funs

        -- Imported value which we have arity information for.
        | ImportValueModule _mn n' tVal (Just (iTypes, iValues, iBoxes)) <- is
        = let
                (bsParam, tBody)        = fromMaybe ([], tVal) $ takeTForalls tVal
                ksParam                 = map typeOfBind bsParam
                ([], tsParam, _tResult) = takeTFunWitArgResult tBody

                csType  = map Call.ConsType  ksParam
                csValue = map Call.ConsValue tsParam
                csBox   = replicate iBoxes Call.ConsBox
                cons    = csType ++ csValue ++ csBox

                -- Check that the the arity information matches the imported
                -- type of the value.
          in    if  (iTypes  == length ksParam)
                 && (iValues <= length tsParam)
                 then Map.insert n (FunExternSuper n' tVal (Just cons)) funs

                 -- TODO: better error, lift into exception.
                 else error "funMapAddForeign: arity type mismatch"


        -- Imported foreign function from Sea land.
        | ImportValueSea _ tVal  <- is
        = let   
                (bsParam, tBody1)       = fromMaybe ([], tVal) $ takeTForalls tVal
                ksParam                 = map typeOfBind bsParam
                ([], tsParam, tBody2)   = takeTFunWitArgResult tBody1
                (esEffs, _tResult)      = takeTSusps tBody2

                csType  = map Call.ConsType  ksParam
                csValue = map Call.ConsValue tsParam
                csBox   = replicate (length esEffs) Call.ConsBox
                cons    = csType ++ csValue ++ csBox

          in    Map.insert n (FunForeignSea n tVal cons) funs


        | otherwise
        = funs


---------------------------------------------------------------------------------------------------
-- | Wrap an expression in the given number of 'run' casts.
-- 
--   TODO: shift into core compounds
--
makeRuns :: a
        -> Int 
        -> Exp a Name 
        -> Exp a Name

makeRuns _a 0 x = x
makeRuns a n x  = XCast a CastRun (makeRuns a (n - 1) x)



