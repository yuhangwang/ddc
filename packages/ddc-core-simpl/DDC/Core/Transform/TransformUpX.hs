
-- | General purpose tree walking boilerplate.
module DDC.Core.Transform.TransformUpX
        ( TransformUpMX(..)
        , transformUpX
        , transformUpX'

          -- * Via the Simple AST
        , transformSimpleUpMX
        , transformSimpleUpX
        , transformSimpleUpX')
where
import DDC.Core.Module
import DDC.Core.Exp.Annot
import DDC.Core.Transform.Annotate
import DDC.Core.Transform.Deannotate
import Data.Functor.Identity
import Control.Monad
import DDC.Core.Env.EnvX                        (EnvX)
import qualified DDC.Core.Exp.Simple.Exp        as S
import qualified DDC.Core.Env.EnvX              as EnvX


-- | Bottom up rewrite of all core expressions in a thing.
transformUpX
        :: forall (c :: * -> * -> *) a n
        .  (Ord n, TransformUpMX Identity c)
        => (EnvX n -> Exp a n -> Exp a n)       
                        -- ^ The worker function is given the current kind and type environments.
        -> EnvX n       -- ^ Initial environment.
        -> c a n        -- ^ Transform this thing.
        -> c a n

transformUpX f env xx
        = runIdentity 
        $ transformUpMX (\env' x -> return (f env' x)) env xx


-- | Like transformUpX, but without using environments.
transformUpX'
        :: forall (c :: * -> * -> *) a n
        .  (Ord n, TransformUpMX Identity c)
        => (Exp a n -> Exp a n)       
                        -- ^ The worker function is given the current
                        --      kind and type environments.
        -> c a n        -- ^ Transform this thing.
        -> c a n

transformUpX' f xx
        = transformUpX (\_ -> f) EnvX.empty xx


-------------------------------------------------------------------------------
class TransformUpMX m (c :: * -> * -> *) where
 -- | Bottom-up monadic rewrite of all core expressions in a thing.
 transformUpMX
        :: Ord n
        => (EnvX n -> Exp a n -> m (Exp a n))
                        -- ^ The worker function is given the current
                        --      kind and type environments.
        -> EnvX n       -- ^ Initial environment.
        -> c a n        -- ^ Transform this thing.
        -> m (c a n)


instance Monad m => TransformUpMX m Module where
 transformUpMX f env !mm
  = do  x'    <- transformUpMX f env $ moduleBody mm
        return  $ mm { moduleBody = x' }


instance Monad m => TransformUpMX m Exp where
 transformUpMX f env !xx
  = (f env =<<)
  $ case xx of
        XVar{}          -> return xx
        XCon{}          -> return xx

        XLAM a b x1
         -> liftM3 XLAM (return a) (return b)
                        (transformUpMX f (EnvX.extendT b env) x1)

        XLam a b  x1    
         -> liftM3 XLam (return a) (return b) 
                        (transformUpMX f (EnvX.extendX b env) x1)

        XApp a x1 x2    
         -> liftM3 XApp (return a) 
                        (transformUpMX f env x1) 
                        (transformUpMX f env x2)

        XLet a lts x
         -> do  lts'      <- transformUpMX f env lts

                let env'  = EnvX.extendsX (valwitBindsOfLets lts')
                          $ EnvX.extendsT (specBindsOfLets lts')   
                          $ env

                x'        <- transformUpMX f env' x
                return  $ XLet a lts' x'
                
        XCase a x alts
         -> liftM3 XCase (return a)
                         (transformUpMX f env x)
                         (mapM (transformUpMX f env) alts)

        XCast a c x       
         -> liftM3 XCast
                        (return a) (return c)
                        (transformUpMX f env x)

        XType{}         -> return xx
        XWitness{}      -> return xx


instance Monad m => TransformUpMX m Lets where
 transformUpMX f env xx
  = case xx of
        LLet b x
         -> liftM2 LLet (return b)
                        (transformUpMX f env x)
        
        LRec bxs
         -> do  let (bs, xs) = unzip bxs
                let env'     = EnvX.extendsX bs env
                xs'          <- mapM (transformUpMX f env') xs
                return       $ LRec $ zip bs xs'

        LPrivate{}      -> return xx


instance Monad m => TransformUpMX m Alt where
 transformUpMX f env alt
  = case alt of
        AAlt p@(PData _ bsArg) x
         -> let env'    = EnvX.extendsX bsArg env
            in  liftM2  AAlt (return p) 
                        (transformUpMX f env' x)

        AAlt PDefault x
         ->     liftM2  AAlt (return PDefault)
                        (transformUpMX f env x) 


-- Simple ---------------------------------------------------------------------
-- | Like `transformUpMX`, but the worker takes the Simple version of the AST.
--
--   * To avoid repeated conversions between the different versions of the AST,
--     the worker should return `Nothing` if the provided expression is unchanged.
transformSimpleUpMX 
        :: (Ord n, TransformUpMX m c, Monad m)
        => (EnvX n -> S.Exp a n -> m (Maybe (S.Exp a n)))
                        -- ^ The worker function is given the current
                        --     kind and type environments.
        -> EnvX n       -- ^ Initial type environment.
        -> c a n        -- ^ Transform thing thing.
        -> m (c a n)

transformSimpleUpMX f env0 xx0
 = let  
        f' env xx
         = do   let a    = annotOfExp xx
                let sxx  = deannotate (const Nothing) xx
                msxx'    <- f env sxx
                case msxx' of
                     Nothing   -> return $ xx
                     Just sxx' -> return $ annotate a sxx'

   in   transformUpMX f' env0 xx0


-- | Like `transformUpX`, but the worker takes the Simple version of the AST.
--
--   * To avoid repeated conversions between the different versions of the AST,
--     the worker should return `Nothing` if the provided expression is unchanged.
transformSimpleUpX
        :: forall (c :: * -> * -> *) a n
        .  (Ord n, TransformUpMX Identity c)
        => (EnvX n -> S.Exp a n -> Maybe (S.Exp a n))
                        -- ^ The worker function is given the current
                        --     kind and type environments.
        -> EnvX n       -- ^ Initial type environment.
        -> c a n        -- ^ Transform this thing.
        -> c a n

transformSimpleUpX f env xx
        = runIdentity 
        $ transformSimpleUpMX 
                (\env' x -> return (f env' x)) env xx


-- | Like `transformUpX'`, but the worker takes the Simple version of the AST.
--
--   * To avoid repeated conversions between the different versions of the AST,
--     the worker should return `Nothing` if the provided expression is unchanged.
transformSimpleUpX'
        :: forall (c :: * -> * -> *) a n
        .  (Ord n, TransformUpMX Identity c)
        => (S.Exp a n -> Maybe (S.Exp a n))
                        -- ^ The worker function is given the current
                        --      kind and type environments.
        -> c a n        -- ^ Transform this thing.
        -> c a n

transformSimpleUpX' f xx
        = transformSimpleUpX (\_ -> f) EnvX.empty xx

