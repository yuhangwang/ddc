-- | Check the kind of a type.
module DDC.Type.Check
        ( Config        (..)
        , configOfProfile

          -- * Checking types.
        , checkType
        , checkTypeM

          -- * Wrappers for specific universes.
        , checkSpec
        , kindOfSpec
        , sortOfKind

          -- * Kinds of Constructors
        , takeSortOfKiCon
        , kindOfTwCon
        , kindOfTcCon
        
          -- * Errors
        , Error         (..)
        , ErrorData     (..))
where
import DDC.Type.Check.Judge.Kind
import DDC.Type.Check.Context
import DDC.Type.Check.Error
import DDC.Type.Check.ErrorMessage      ()
import DDC.Type.Check.CheckCon
import DDC.Type.Check.Config
import DDC.Type.Exp.Simple
import DDC.Type.Universe
import DDC.Base.Pretty
import DDC.Control.Monad.Check           (evalCheck)


-- | Check a type in the given universe with the given environment
--   Returns the updated type and its classifier (a kind or sort),
--   depeding on the universe of the type being checked.
checkType  :: (Ord n, Show n, Pretty n)
           => Config n -> Universe -> Type n
           -> Either (Error n) (Type n, Type n)

checkType config uni tt
 = evalCheck (0, 0)
 $ do   (t, k, _) <- checkTypeM config emptyContext uni tt Recon
        return (t, k)


-- | Check a spec in the given environment, returning an error or its kind.
checkSpec  :: (Ord n, Show n, Pretty n) 
           => Config n -> Type n
           -> Either (Error n) (Type n, Kind n)

checkSpec config tt 
 = evalCheck (0, 0)
 $ do   (t, k, _) <- checkTypeM config emptyContext UniverseSpec tt Recon
        return (t, k)


-- | Check a spec in an empty environment, returning an error or its kind.
kindOfSpec
        :: (Ord n, Show n, Pretty n) 
        => Config n -> Type n 
        -> Either (Error n) (Kind n)

kindOfSpec config tt
 = evalCheck (0, 0)
 $ do   (_, k, _) <- checkTypeM config emptyContext UniverseSpec tt Recon
        return k


-- | Check a kind in an empty environment, returning an error or its sort.
sortOfKind 
        :: (Ord n, Show n, Pretty n)
        => Config n -> Kind n
        -> Either (Error n) (Sort n)

sortOfKind config tt
 = evalCheck (0, 0)
 $ do   (_, s, _) <- checkTypeM config emptyContext UniverseKind tt Recon
        return s

