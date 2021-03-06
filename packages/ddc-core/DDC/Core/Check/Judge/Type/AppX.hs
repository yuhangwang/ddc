
module DDC.Core.Check.Judge.Type.AppX
        (checkAppX)
where
import DDC.Core.Check.Judge.Type.Sub
import DDC.Core.Check.Judge.Type.Base
import qualified DDC.Type.Sum   as Sum


-------------------------------------------------------------------------------
-- | Check a value expression application.
checkAppX :: Checker a n

checkAppX !table !ctx Recon demand
        xx@(XApp a xFn xArg)
 = do
        -- Check the functional expression.
        (xFn',  tFn,  effsFn, ctx1)
         <- tableCheckExp table table ctx  Recon demand xFn

        -- Check the argument.
        (xArg', tArg, effsArg, ctx2)
         <- tableCheckExp table table ctx1 Recon DemandNone xArg

        -- The type of the parameter must match that of the argument.
        (tResult, effsLatent)
         <- case splitFunType tFn of
             Just (tParam, effs, _, tResult)
              |  equivT (contextEnvT ctx2) tParam tArg
              -> return (tResult, effs)

              | otherwise
              -> throw  $ ErrorAppMismatch a xx tParam tArg

             Nothing
              -> throw  $ ErrorAppNotFun a xx tFn

        -- Effect of the overall application.
        let effsResult  
                = Sum.unions kEffect
                $ [effsFn, effsArg, Sum.singleton kEffect effsLatent]

        returnX a
                (\z -> XApp z xFn' xArg')
                tResult effsResult
                ctx2


checkAppX !table !ctx0 Synth demand 
        xx@(XApp a xFn xArg)
 = do
        ctrace  $ vcat
                [ text "*>  App Synth"
                , empty ]

        -- Synth a type for the functional expression.
        (xFn', tFn, effsFn, ctx1)
         <- tableCheckExp table table ctx0 Synth demand xFn

        -- Substitute context into synthesised type.
        tFn' <- applyContext ctx1 tFn

        -- Synth a type for the function applied to its argument.
        (xResult, tResult, esResult, ctx2)
         <- synthAppArg table a xx ctx1 demand
                xFn' tFn' effsFn xArg

        ctrace  $ vcat
                [ text "*<  App Synth"
                , text "    demand  : " <> (text $ show demand)
                , indent 4 $ ppr xx
                , text "    tFn     : " <> ppr tFn'
                , text "    tArg    : " <> ppr xArg
                , text "    xResult : " <> ppr xResult
                , text "    tResult : " <> ppr tResult
                , indent 4 $ ppr ctx0
                , indent 4 $ ppr ctx2
                , empty ]

        return  (xResult, tResult, esResult, ctx2)


checkAppX !table !ctx (Check tExpected) demand 
        xx@(XApp a _ _) 
 = do   
        ctrace  $ vcat
                [ text "*>  App Check"
                , text "    tExpected: " <> ppr tExpected
                , empty ]

        result  <- checkSub table a ctx demand xx tExpected

        ctrace  $ vcat
                [ text "*<  App Check"
                , empty ]

        return  result   

checkAppX _ _ _ _ _
 = error "ddc-core.checkApp: no match"


-------------------------------------------------------------------------------
-- | Synthesize the type of a function applied to its argument.
synthAppArg
        :: (Show a, Show n, Ord n, Pretty n)
        => Table a n
        -> a                         -- Annot for error messages.
        -> Exp a n                   -- Expression for error messages.
        -> Context n                 -- Current context.
        -> Demand                    -- Demand placed on result of application.
        -> Exp (AnTEC a n) n         -- Checked functional expression.
                -> Type n            -- Type of functional expression.
                -> TypeSum n         -- Effect of functional expression.
        -> Exp a n                   -- Function argument.
        -> CheckM a n
                ( Exp (AnTEC a n) n  -- Checked application.
                , Type n             -- Type of result.
                , TypeSum n          -- Effect of result.
                , Context n)         -- Result context.

synthAppArg table a xx ctx0 demand xFn tFn effsFn xArg

 -- Rule (App Synth exists)
 --  Functional type is an existential.
 | Just iFn      <- takeExists tFn
 = do
        ctrace  $ vcat
                [ text "*>  App Synth Exists"
                , empty ]

        -- New existential for the type of the function parameter.
        iA1      <- newExists kData
        let tA1  = typeOfExists iA1

        -- New existential for the type of the function result.
        iA2      <- newExists kData
        let tA2  = typeOfExists iA2

        -- Update the context with the new constraint.
        let Just ctx1 = updateExists [iA2, iA1] iFn (tFun tA1 tA2) ctx0

        -- Check the argument under the new context.
        (xArg', _, effsArg, ctx2)
         <- tableCheckExp table table ctx1 (Check tA1) DemandRun xArg

        -- Effect and closure of the overall function application.
        let esResult    = effsFn `Sum.union` effsArg

        -- Result expression.
        let xResult    = XApp  (AnTEC tA2 (TSum esResult) (tBot kClosure) a)
                                xFn xArg'

        ctrace  $ vcat
                [ text "*<  App Synth Exists"
                , text "    xFn    :"  <> ppr xFn
                , text "    tFn    :"  <> ppr tFn
                , text "    xArg   :"  <> ppr xArg
                , text "    xArg'  :"  <> ppr xArg'
                , text "    xResult:"  <> ppr xResult
                , indent 4 $ ppr xx
                , indent 4 $ ppr ctx2
                , empty ]

        return  (xResult, tA2, esResult, ctx2)


 -- Rule (App Synth Forall)
 --  Function has a quantified type, but we're applying an expression to it.
 --  We need to inject a new type argument.
 | TForall b tBody      <- tFn
 = do
        ctrace  $ vcat
                [ text "*>  App Synth Forall"
                , empty ]

        -- Make a new existential for the type of the argument,
        -- and push it onto the context.
        iA         <- newExists (typeOfBind b)
        let tA     = typeOfExists iA
        let ctx1   = pushExists iA ctx0

        -- Instantiate the type of the function with the new existential.
        let tBody' = substituteT b tA tBody

        -- Add the missing type application.
        --  Because we were applying a function to an expression argument,
        --  and the type of the function was quantified, we know there should
        --  be a type application here.
        let aFn    = AnTEC tFn (TSum effsFn) (tBot kClosure) a
        let aArg   = AnTEC (typeOfBind b) (tBot kEffect) (tBot kClosure) a
        let xFnTy  = XApp aFn xFn (XType aArg tA)

        -- Synthesise the result type of a function being applied to its
        -- argument. We know the type of the function up-front, but we pass
        -- in the whole argument expression.
        (xResult, tResult, esResult, ctx2)
         <- synthAppArg table a xx ctx1 demand xFnTy tBody' effsFn xArg

        -- Result expression.

        ctrace  $ vcat
                [ text "*<  App Synth Forall"
                , text "    xFn     : " <> ppr xFn
                , text "    tFn     : " <> ppr tFn
                , text "    xArg    : " <> ppr xArg
                , text "    xResult : " <> ppr xResult
                , text "    tResult : " <> ppr tResult
                , indent 4 $ ppr ctx2
                , empty ]

        return  (xResult, tResult, esResult, ctx2)


 -- Rule (App Synth Fun)
 --  Function already has a concrete function type.
 | Just (tParam, tResult)   <- takeTFun tFn
 = do
        ctrace  $ vcat
                [ text "*>  App Synth Fun"
                , empty ]

        -- Check the argument.
        (xArg', tArg, esArg, ctx1)
         <- tableCheckExp table table ctx0 (Check tParam) DemandRun xArg

        tFn'     <- applyContext ctx1 tFn
        tArg'    <- applyContext ctx1 tArg
        tResult' <- applyContext ctx1 tResult

        -- Get the type, effect and closure resulting from the application
        -- of a function of this type to its argument.
        esLatent
         <- case splitFunType tFn' of
             Just (_tParam, effsLatent, _closLatent, _tResult)
              -> return effsLatent

             -- This shouldn't happen because this rule (App Synth Fun) only
             -- applies when 'tFn' is has a functional type, and applying
             -- the current context to it as above should not change this.
             Nothing
              -> error "ddc-core.synthAppArg: unexpected type of function."


        -- Result of evaluating the functional expression applied
        -- to its argument.
        let esExp       = Sum.unions kEffect
                        $ [ effsFn, esArg, Sum.singleton kEffect esLatent]

        -- The checked application.
        let xExp'       = XApp  (AnTEC tResult' (TSum esExp) (tBot kClosure) a)
                                xFn xArg'

        -- If the function returns a suspension then automatically run it.
        let (xExpRun, tExpRun, esExpRun)
                | configImplicitRun (tableConfig table)
                , DemandRun     <- demand
                , Just (eExpRun', tExpRun') <- takeTSusp tResult'
                = let   
                        eTotal  = tSum kEffect [TSum esExp, eExpRun']

                  in    ( XCast (AnTEC tResult' eTotal (tBot kClosure) a)
                                CastRun xExp'
                        , tExpRun'
                        , Sum.fromList kEffect [eTotal])

                | otherwise
                =       ( xExp'
                        , tResult'
                        , esExp)

        ctrace  $ vcat
                [ text "*<  App Synth Fun"
                , indent 4 $ ppr xx
                , text "    xArg    : " <> ppr xArg
                , text "    tFn'    : " <> ppr tFn'
                , text "    tArg'   : " <> ppr tArg'
                , text "    xArg'   : " <> ppr xArg'
                , text "    xExpRun : " <> ppr xExpRun
                , text "    tExpRun : " <> ppr tExpRun
                , indent 4 $ ppr ctx1
                , empty ]

        return  (xExpRun, tExpRun, esExpRun, ctx1)


 -- Applied expression is not a function.
 | otherwise
 =      throw $ ErrorAppNotFun a xx tFn


-------------------------------------------------------------------------------
-- | Split a function-ish type into its parts.
--   This works for implications, as well as the function constructor
--   with and without a latent effect.
splitFunType :: Type n -> Maybe (Type n, Effect n, Closure n, Type n)
splitFunType tt
 = case tt of
        TApp (TApp (TCon (TyConWitness TwConImpl)) t11) t12
          -> Just (t11, tBot kEffect, tBot kClosure, t12)

        TApp (TApp (TCon (TyConSpec TcConFun)) t11) t12
          -> Just (t11, tBot kEffect, tBot kClosure, t12)

        _ -> Nothing

