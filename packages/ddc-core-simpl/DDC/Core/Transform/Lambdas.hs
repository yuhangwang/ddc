
module DDC.Core.Transform.Lambdas
        (lambdasModule)
where
import DDC.Core.Fragment
import DDC.Core.Collect.Support
import DDC.Core.Transform.SubstituteXX
import DDC.Core.Module
import DDC.Core.Exp.Annot.Context
import DDC.Core.Exp.Annot.Ctx
import DDC.Core.Exp.Annot
import DDC.Type.Transform.SubstituteT
import DDC.Type.Collect
import DDC.Base.Pretty
import DDC.Base.Name
import Data.Function
import Data.List
import Data.Set                         (Set)
import Data.Map                         (Map)
import qualified DDC.Core.Check         as Check
import qualified DDC.Type.Env           as Env
import qualified DDC.Type.DataDef       as DataDef
import qualified Data.Set               as Set
import qualified Data.Map               as Map
import qualified DDC.Core.Env.EnvX      as EnvX
import Data.Maybe


---------------------------------------------------------------------------------------------------
-- | Perform lambda lifting in a module.
lambdasModule 
        :: ( Show a, Pretty a
           , Show n, Pretty n, Ord n, CompoundName n)
        => Profile n
        -> Module a n -> Module a n

lambdasModule profile mm
 = let  
        -- Take the top-level environment of the module.
        env     = moduleEnvX 
                        (profilePrimKinds    profile)
                        (profilePrimTypes    profile)
                        (profilePrimDataDefs profile)
                        mm

        c       = Context env (CtxTop env)

        x'      = lambdasLoopX profile c $ moduleBody mm

   in   beautifyModule
         $ mm { moduleBody = x' }


---------------------------------------------------------------------------------------------------
-- | Result of lambda lifter recursion.
data Result a n
        = Result
        { -- | Whether we've made any progress in this pass.
          _resultProgress       :: Bool        

          -- | Bindings that we've already lifted out, 
          --   and should be added at top-level.
        , _resultBindings       :: [(Bind n, Exp a n)]
        }


instance Monoid (Result a n) where
 mempty
  = Result False []
 
 mappend (Result p1 lts1) (Result p2 lts2)
  = Result (p1 || p2) (lts1 ++ lts2)


-- Exp --------------------------------------------------------------------------------------------
lambdasLoopX
         :: (Show n, Show a, Pretty n, Pretty a, CompoundName n, Ord n)
         => Profile n           -- ^ Language profile.
         -> Context a n         -- ^ Enclosing context.
         -> Exp a n             -- ^ Expression to perform lambda lifting on.
         -> Exp a n             --   Replacement expression.
        
lambdasLoopX p c xx
 = let  (xx1, Result progress _)   = lambdasTopX p c xx
   in   if progress then lambdasLoopX p c xx1
                    else xx1

-- | Handle the expression that defines the body of the module
--   separately. The body is a letrec that contains the top level
--   bindings, and we don't want to lift them out further.
lambdasTopX p c xx
 = case xx of
        XLet a lts xBody
         -> let (lts', r1)      = lambdasTopLets p c a xBody lts 
                (x',   r2)      = enterLetBody   c a lts xBody  (lambdasTopX p)
            in  ( foldr (XLet a) x' lts'
                , mappend r1 r2)

        _ -> lambdasX p c xx


-- | Handle the top-level group of bindings.
lambdasTopLets p c a xBody lts
 = case lts of
        LRec bxs
          -> let (bxs', r) = lambdasLetRec p c a [] bxs xBody
             in  ([LRec bxs'], r)

        _ -> lambdasLets p c a xBody lts


---------------------------------------------------------------------------------------------------
-- | Perform a single pass of lambda lifting in an expression.
lambdasX :: (Show n, Show a, Pretty n, Pretty a, CompoundName n, Ord n)
         => Profile n           -- ^ Language profile.
         -> Context a n         -- ^ Enclosing context.
         -> Exp a n             -- ^ Expression to perform lambda lifting on.
         -> ( Exp a n           --   Replacement expression
            , Result a n)       --   Lifter result.
         
lambdasX p c xx
 = case xx of
        XVar{}  -> (xx, mempty)
        XCon{}  -> (xx, mempty)
         
        -- Lift type lambdas to top-level.
        XLAM a b x0
         -> enterLAM c a b x0 $ \c' x
         -> let (x', r)      = lambdasX p c' x
                xx'          = XLAM a b x'
                Result _ bxs = r
                
                -- Decide whether to lift this lambda to top-level.
                -- If there are multiple nested lambdas then we want to lift
                -- the whole group at once, rather than lifting each one 
                -- individually.
                liftMe       =  isLiftyContext (contextCtx c)   && null bxs
                
            in if liftMe
                then  let us'   = supportEnvFlags
                                $ support Env.empty Env.empty xx'
                          
                          (xCall, bLifted, xLifted)
                                = liftLambda p c us' a [(True, b)] x'

                      in  ( xCall
                          , Result True (bxs ++ [(bLifted, xLifted)]))

                else (xx', r)


        -- Lift value lambdas to top-level.
        XLam a b x0
         -> enterLam c a b x0 $ \c' x
         -> let (x', r)      = lambdasX p c' x
                xx'          = XLam a b x'
                Result _ bxs = r
                
                -- Decide whether to lift this lambda to top-level.
                liftMe       =  isLiftyContext (contextCtx c)  && null bxs

            in if liftMe
                then  let us'   = supportEnvFlags
                                $ support Env.empty Env.empty xx'

                          (xCall, bLifted, xLifted)
                                = liftLambda p c us' a [(False, b)] x'
                      
                      in  ( xCall
                          , Result True (bxs ++ [(bLifted, xLifted)]))
                else (xx', r)


        -- Lift suspensions to top-level.
        --   These behave like zero-arity lambda expressions,
        --   they suspend evaluation but do not abstract over a value.
        XCast a cc@CastBox x0
         -> enterCastBody c a cc x0 $ \c' x
         -> let (x', r)      = lambdasX p c' x
                xx'          = XCast a CastBox x'
                Result _ bxs = r

                -- Decide whether to lift this box to top-level.
                liftMe       =  isLiftyContext (contextCtx c)  && null bxs

            in if liftMe 
                then let us' = supportEnvFlags
                             $ support Env.empty Env.empty xx'

                         (xCall, bLifted, xLifted)
                             = liftLambda p c us' a [] (XCast a CastBox x')

                     in  ( xCall
                         , Result True (bxs ++ [(bLifted, xLifted)]))

                else (xx', r)


        -- Eta-expand partially applied data contructors.
        XApp a x1 x2
         | (xCon@(XCon _a (DaConBound nCon)), xsArg)   <- takeXApps1 x1 x2
         -> let ctx     = contextCtx c
                envX    = topOfCtx ctx
                defs    = EnvX.envxDataDefs envX

            in  case Map.lookup nCon (DataDef.dataDefsCtors defs) of
                 Just dataCtor
                  -- We check for partial application on the outside of a
                  -- set of nested applications.
                  |  case ctx of
                        CtxAppLeft{}    -> False
                        _               -> True

                  -- We're expecting an argument for each of the type and term parameters.
                  ,  arityT <- length $ DataDef.dataCtorTypeParams dataCtor
                  ,  arityX <- length $ DataDef.dataCtorFieldTypes dataCtor
                  ,  arity  <- arityT + arityX

                  -- See if we have the correct number of arguments.
                  ,  args  <- length xsArg
                  ,  arity /= args
                  -> let 
                         -- TODO: needing to generate names like this is ugly.
                         -- Should have just used a state monad.
                         bsT       = [ BName (nameOfContext ("Lift_" ++ show i) c) (typeOfBind b)
                                        | i <- [0 .. arityT - 1]
                                        | b <- DataDef.dataCtorTypeParams dataCtor ]

                         Just usT  = sequence $ map takeSubstBoundOfBind bsT

                         sub       = zip (DataDef.dataCtorTypeParams dataCtor) 
                                         (map TVar usT)

                         bsX       = [ BName (nameOfContext ("Lift_" ++ show i) c) 
                                             (substituteTs sub t)
                                        | i <- [0 .. arityX - 1]
                                        | t <- DataDef.dataCtorFieldTypes dataCtor]

                         Just usX     = sequence $ map takeSubstBoundOfBind bsX
                         downArg xArg = enterAppRight c a x1 xArg (lambdasX p)
                         (xsArg', rs) = unzip $ map downArg xsArg

                     in ( xApps a
                                ( xLAMs a bsT $ xLams a bsX 
                                        $  xApps a xCon
                                        $  [ XType a (TVar u) | u <- usT]
                                        ++ [ XVar a u         | u <- usX])
                                xsArg'

                        , mconcat rs)

                 _
                  -> let (x1', r1) = enterAppLeft  c a x1 x2 (lambdasX p)
                         (x2', r2) = enterAppRight c a x1 x2 (lambdasX p)
                     in  ( XApp a x1' x2'
                         , mappend r1 r2)


        -- Boilerplate.
        XApp a x1 x2
         -> let (x1', r1)       = enterAppLeft  c a x1 x2 (lambdasX p)
                (x2', r2)       = enterAppRight c a x1 x2 (lambdasX p)
            in  ( XApp a x1' x2'
                , mappend r1 r2)
                
        XLet a lts x
         -> let (lts', r1)      = lambdasLets  p c a x lts 
                (x',   r2)      = enterLetBody c a lts x  (lambdasX p)
            in  ( foldr (XLet a) x' lts'
                , mappend r1 r2)
                
        XCase a x alts
         -> let (x',    r1)     = enterCaseScrut c a x alts (lambdasX p)
                (alts', r2)     = lambdasAlts  p c a x [] alts
            in  ( XCase a x' alts'
                , mappend r1 r2)

        XCast a cc x
         ->     lambdasCast p c a cc x
                
        XType{}         -> (xx, mempty)
        XWitness{}      -> (xx, mempty)


-- Lets -------------------------------------------------------------------------------------------
-- | Perform lambda lifting in some let-bindings.
lambdasLets
        :: (Show a, Show n, Ord n, Pretty n, Pretty a, CompoundName n)
        => Profile n -> Context a n
        -> a -> Exp a n
        -> Lets a n
        -> ([Lets a n], Result a n)
           
lambdasLets p c a xBody lts
 = case lts of
        LLet b x
         -> let (x', r)   = enterLetLLet c a b x xBody (lambdasX p)
            in  ([LLet b x'], r)

        LRec bxs
         -> let (bxs', r) = lambdasLetRecLiftAll p c a bxs
            in  (map (uncurry LLet) bxs', r)

        LPrivate{}
         -> ([lts], mempty)


-- LetRec -----------------------------------------------------------------------------------------
-- | Perform lambda lifting in the right of a single let-rec binding.
lambdasLetRec 
        :: (Show a, Show n, Ord n, Pretty n, Pretty a, CompoundName n)
        => Profile n -> Context a n
        -> a -> [(Bind n, Exp a n)] -> [(Bind n, Exp a n)] -> Exp a n
        -> ([(Bind n, Exp a n)], Result a n)

lambdasLetRec _ _ _ _ [] _
        = ([], mempty)

lambdasLetRec p c a bxsAcc ((b, x) : bxsMore) xBody
 = let  (x',   r1) = enterLetLRec  c a bxsAcc b x bxsMore xBody (lambdasX p)

   in   case contextCtx c of

         -- If we're at top-level then drop lifted bindings here.
         CtxTop{}
          -> let  (bxs', Result p2 bxs2) 
                        = lambdasLetRec p c a ((b, x') : bxsAcc) bxsMore xBody
                  Result p1 bxsLifted = r1
             in   ( bxsLifted ++ ((b, x') : bxs')
                  , Result (p1 || p2) bxs2 )

         _
          -> let  (bxs', r2) = lambdasLetRec p c a ((b, x') : bxsAcc) bxsMore xBody
             in   ( (b, x') : bxs'
                  , mappend r1 r2 )


-- | When all the bindings in a letrec are lambdas, lift them all together.
lambdasLetRecLiftAll
        :: (Show a, Show n, Ord n, Pretty n, Pretty a, CompoundName n)
        => Profile n -> Context a n
        -> a
        -> [(Bind n, Exp a n)]
        -> ([(Bind n, Exp a n)], Result a n)

lambdasLetRecLiftAll p c a bxs
 = let 
       -- The union of free variables of all the mutually recursive bindings must be used,
       -- as any lifted function may call the other lifted functions.
       us   = Set.unions
            $ map (supportEnvFlags . support Env.empty Env.empty)
            $ map snd bxs

       -- However, the functions we are lifting should not be treated as free variables
       us'  = Set.filter 
                (\(_, bo) -> not $ any (boundMatchesBind bo . fst) bxs)
            $ us

       -- Lift each of the bindings in its own context.
       --  We allow the group of bindings to contain ones with outer lambda
       --  abstractions that need to be lifted, along with non-functional
       --  bindings that stay in place.
       lift _before [] 
        = []

       lift before ((b, x) : after)
        = case takeXLamFlags x of
                -- The right of this binding has an outer abstraction, 
                -- so we need to lift it to top-level.
                Just (lams, xx)
                 -> let c' = ctx before b x after
                        l' = liftLambda p c' us' a lams xx

                    in  Right (b, l') : lift (before ++ [(b,x)]) after

                -- The right of this binding does not have any outer
                -- abstractions, so we can leave it in place.
                Nothing
                 ->     Left (b, x)   : lift (before ++ [(b, x)]) after

       ls    = lift [] bxs

       -- The call to each lifted function
       stripCall (Left  (b, x))          = (b, x)
       stripCall (Right (b, (xC, _, _))) = (b, xC)
       calls = map stripCall ls

       -- Substitute the original name of the recursive function with a call to its new name,
       -- including passing along any free variables.
       -- Here, we need to unwrap the newly-created lambdas for the free variables,
       -- as capture-avoiding substitution would rename them - the opposite of what we want.
       sub x = case takeXLamFlags x of
                Just (lams, xx) -> makeXLamFlags a lams (substituteXXs calls xx)
                Nothing         ->                       substituteXXs calls x

       -- The result bindings to add at the top-level, with all the new names substituted in
       stripResult (Left _)                 = Nothing
       stripResult (Right (_, (_, bL, xL))) = Just (bL, sub xL)
       res  = mapMaybe stripResult ls

   in  (calls, Result True res)

 where
  -- Wrap the context in the letrec
  ctx before b x after
   = enterLetLRec c a before b x after x (\c' _ -> c')


-- Alts -------------------------------------------------------------------------------------------
-- | Perform lambda lifting in the right of a single alternative.
lambdasAlts 
        :: (Show a, Show n, Ord n, Pretty n, Pretty a, CompoundName n)
        => Profile n -> Context a n
        -> a -> Exp a n -> [Alt a n] -> [Alt a n]
        -> ([Alt a n], Result a n)
           
lambdasAlts _ _ _ _ _ []
        = ([], mempty)

lambdasAlts p c a xScrut altsAcc (AAlt w x : altsMore)
 = let  (x', r1)    = enterCaseAlt   c a xScrut altsAcc w x altsMore (lambdasX p)
        (alts', r2) = lambdasAlts  p c a xScrut (AAlt w x' : altsAcc) altsMore
   in   ( AAlt w x' : alts'
        , mappend r1 r2)


-- Cast -------------------------------------------------------------------------------------------
-- | Perform lambda lifting in the body of a Cast expression.
lambdasCast
        :: (Show a, Show n, Ord n, Pretty n, Pretty a, CompoundName n)
        => Profile n -> Context a n
        -> a -> Cast a n -> Exp a n
        -> (Exp a n, Result a n)

lambdasCast p c a cc x
  = case cc of
        CastWeakenEffect{}    
         -> let (x', r) = enterCastBody c a cc x  (lambdasX p)
            in  ( XCast a cc x', r)

        CastPurify{}
         -> let (x', r) = enterCastBody c a cc x  (lambdasX p)
            in  (XCast a cc x',  r)

        CastBox 
         -> let (x', r) = enterCastBody  c a cc x (lambdasX p)
            in  (XCast a cc x',  r)
       
        CastRun 
         -> let (x', r)  = enterCastBody c a cc x (lambdasX p)
            in  (XCast a cc x',  r)


---------------------------------------------------------------------------------------------------
-- | Check if this is a context that we should lift lambda abstractions out of.
isLiftyContext :: Ctx a n -> Bool
isLiftyContext ctx
 = case ctx of
        -- Don't lift out of the top-level context.
        -- There's nowhere else to lift to.
        CtxTop{}        -> False
        CtxLetLLet{}    -> not $ isTopLetCtx ctx
        CtxLetLRec{}    -> not $ isTopLetCtx ctx

        -- Don't lift if we're inside more lambdas.
        --  We want to lift the whole binding group together.
        CtxLAM{}        -> False
        CtxLam{}        -> False
   
        -- We can't do code generation for abstractions in these contexts,
        -- so they need to be lifted.
        CtxAppLeft{}    -> True
        CtxAppRight{}   -> True
        CtxLetBody{}    -> True
        CtxCaseScrut{}  -> True
        CtxCaseAlt{}    -> True
        CtxCastBody{}   -> True


---------------------------------------------------------------------------------------------------
-- | Construct the call site, and new lifted binding for a lambda lifted
--   abstraction.
liftLambda 
        :: (Show a, Show n, Pretty n, Ord n, CompoundName n, Pretty a)
        => Profile n            -- ^ Language profile.
        -> Context a n          -- ^ Context of the original abstraction.
        -> Set (Bool, Bound n)  -- ^ Free variables in the body of the abstraction.
        -> a
        -> [(Bool, Bind n)]     -- ^ The lambdas, and whether they are type or value
        -> Exp a n
        -> (  Exp a n
            , Bind n, Exp a n)

liftLambda p c fusFree a lams xBody
 = let  ctx             = contextCtx c

        -- The complete abstraction that we're lifting out.
        xLambda         = makeXLamFlags a lams xBody

        -- Name of the enclosing top-level binding.
        Just nTop       = takeTopNameOfCtx ctx

        -- Names of other supers bound at top-level.
        nsSuper         = takeTopLetEnvNamesOfCtx ctx

        -- Name of the new lifted binding.
        nLifted         = extendName nTop ("Lift_" ++ encodeCtx ctx)
        uLifted         = UName nLifted

        -- Build the type checker configuration for this context.
        config          = Check.configOfProfile p
        env             = contextEnv c

        -- Function to get the type of an expression in this context.
        -- If there are type errors in the input program then some 
        -- either the lambda lifter is broken or some other transform
        -- has messed up.
        typeOfExp x
         = case Check.typeOfExp config env x
            of  Left err
                 -> error $ renderIndent $ vcat
                          [ text "ddc-core-simpl.liftLambda: type error in lifted expression"
                          , ppr err]
                Right t -> t


        -- Decide whether we want to bind the given variable as a new parameter
        -- on the lifted super. We don't need to bind primitives, other supers,
        -- or any variable bound by the abstraction itself.
        keepVar fu@(_, u)
         | (False, UName n) <- fu      = not $ Set.member n nsSuper
         | (_,     UPrim{}) <- fu      = False
         | any (boundMatchesBind u . snd) lams
                                       = False
         | otherwise                   = True

        fusFree_filtered
                = filter keepVar
                $ Set.toList fusFree


        -- Join in the types of the free variables.
        joinType (f, u)
         = case f of
            True    | Just t <- EnvX.lookupT u env
                    -> ((f, u), t)

            False   | Just t <- EnvX.lookupX u env
                    -> ((f, u), t)
                
            _       -> error $ unlines
                        [ "ddc-core-simpl.joinType: cannot find type of free var."
                        , show (f, u)
                        , show (Map.keys $ EnvX.envxMap env) ]

        futsFree_types
                = map joinType fusFree_filtered


        -- Add in type variables that are free in the types of free value variables.
        -- We need to bind these as well in the new super.
        expandFree ((f, u), t)
         | False <- f   =  [(f, u)]
                        ++ [(True, ut) | ut  <- Set.toList
                                             $  freeVarsT Env.empty t]
         | otherwise    =  [(f, u)]
    
        fusFree_body    =  [(True, ut) | ut  <- Set.toList 
                                             $  freeVarsT Env.empty $ typeOfExp xLambda]

        futsFree_expandFree
                =  map joinType
                $  Set.toList $ Set.fromList
                $  (concatMap expandFree $ futsFree_types)
                ++ fusFree_body

        -- Sort free vars so the type variables come out the front.
        futsFree
                = sortBy (compare `on` (not . fst . fst))
                $ futsFree_expandFree


        -- At the call site, apply all the free variables of the lifted
        -- function as new arguments.    
        makeArg  (True,  u) = XType a (TVar u)
        makeArg  (False, u) = XVar a u
        
        xCall   = xApps a (XVar a uLifted)
                $ map makeArg $ map fst futsFree


        -- ISSUE #330: Lambda lifter doesn't work with anonymous binders.
        -- For the lifted abstraction, wrap it in new lambdas to bind all of
        -- its free variables. 
        makeBind ((True,  (UName n)), t) = (True,  BName n t)
        makeBind ((False, (UName n)), t) = (False, BName n t)
        makeBind fut
                = error $ "ddc-core-simpl.liftLamba: unhandled binder " ++ show fut
        
        -- Make the new super.
        bsParam = map makeBind futsFree

        xLifted = makeXLamFlags a bsParam xLambda


        -- Get the type of the bound expression, which we need when building
        -- the type of the new super.
        tLifted = typeOfExp xLifted
        bLifted = BName nLifted tLifted
        
    in  ( xCall
        , bLifted, xLifted)


nameOfContext :: CompoundName n => String -> Context a n -> n
nameOfContext prefix c
 = let  ctx             = contextCtx c

        -- Name of the enclosing top-level binding.
        Just nTop       = takeTopNameOfCtx ctx

        -- Name of the new lifted binding.
   in   extendName nTop (prefix ++ encodeCtx ctx)


---------------------------------------------------------------------------------------------------
-- TODO: doing this separate beautify pass was a mistake.
-- Just use a state monad to generate fresh names.

-- | Beautify the names of lifted lamdba abstractions.
--   The lifter itself names new abstractions after the context they come from.
--   This is an easy way of generating unique names, but the names are too
--   verbose to want to show to users, or put in the symbol table of the
--   resulting binary.
--   
--   The beautifier renames the bindings of lifted abstractions to
--    fun$L0, fun$L1 etc, where 'fun' is the name of the top-level binding
--   it was lifted out of.
--
beautifyModule 
        :: forall a n. (Ord n, CompoundName n)
        => Module a n -> Module a n

beautifyModule mm
 = mm { moduleBody = beautifyX $ moduleBody mm }

 where
  -- If the given binder is for an abstraction that we have lifted, 
  -- then produce a new nice name for it.
  makeRenamer 
        ::  Map n Int -> Bind n 
        -> (Map n Int, Maybe (n, (n, Type n)))

  makeRenamer acc b
        | BName n t         <- b
        , Just (nBase, str) <- splitName n
        , isPrefixOf "Lift_" str
        = case Map.lookup nBase acc of
           Nothing  -> ( Map.insert nBase 0 acc
                       , Just (  extendName nBase str
                              , (extendName nBase ("L" ++ show (0 :: Int)), t)))

           Just n'  -> ( Map.insert nBase (n' + 1) acc
                       , Just (  extendName nBase str
                              , (extendName nBase ("L" ++ show (n' + 1)),   t)))

        | otherwise = (acc, Nothing)

  -- Beautify bindings.
  beautifyBXs a bxs
   = let bsRenames   :: [(n, (n, Type n))]
         bsRenames   = catMaybes $ snd
                     $ mapAccumL makeRenamer (Map.empty :: Map n Int)
                     $ map fst bxs

         bxsSubsts   :: [(Bind n, Exp a n)]
         bxsSubsts   =  [ (BName n t, XVar a (UName n'))
                                | (n, (n', t))  <- bsRenames]   

         renameBind (b, x)
                | BName n t     <- b
                , Just  (n', _) <- lookup n bsRenames
                = (BName n' t, x)
                
                | otherwise = (b, x)
            
     in  map (\(b, x) -> (b, substituteXXs bxsSubsts x))
          $ map renameBind bxs

  -- Beautify bindings in top-level let-expressions.
  beautifyX xx
   = case xx of
        XLet a (LRec bxs) xBody
         -> let bxs'    = beautifyBXs a bxs
            in  XLet a (LRec bxs')  (beautifyX xBody)

        XLet a (LLet b x) xBody
         -> let [(b', x')] = beautifyBXs a [(b, x)]
            in  XLet a (LLet b' x') (beautifyX xBody)

        _ -> xx

