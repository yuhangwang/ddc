
module DDC.Core.Exp.Annot
        ( 
         ---------------------------------------
         -- * Abstract Syntax
          module DDC.Type.Exp

         -- ** Expressions
        , Exp           (..)
        , Lets          (..)
        , Alt           (..)
        , Pat           (..)
        , Cast          (..)

          -- ** Witnesses
        , Witness       (..)

          -- ** Data Constructors
        , DaCon         (..)

          -- ** Witness Constructors
        , WiCon         (..)

          ---------------------------------------
          -- * Predicates
        , module DDC.Type.Exp.Simple.Predicates

          -- ** Atoms
        , isXVar,  isXCon
        , isAtomX, isAtomW

          -- ** Lambdas
        , isXLAM, isXLam
        , isLambdaX

          -- ** Applications
        , isXApp

          -- ** Cast
        , isXCast
        , isXCastBox
        , isXCastRun

          -- ** Let bindings
        , isXLet

          -- ** Patterns
        , isPDefault

          -- ** Types and Witnesses
        , isXType
        , isXWitness

          ---------------------------------------
          -- * Compounds
        , module DDC.Type.Exp.Simple.Compounds

          -- ** Annotations
        , annotOfExp
        , mapAnnotOfExp

          -- ** Lambdas
        , xLAMs
        , xLams
        , makeXLamFlags
        , takeXLAMs
        , takeXLams
        , takeXLamFlags

        , Param(..)
        , takeXLamParam

          -- ** Applications
        , xApps
        , makeXAppsWithAnnots
        , takeXApps
        , takeXApps1
        , takeXAppsAsList
        , takeXAppsWithAnnots
        , takeXConApps
        , takeXPrimApps

          -- ** Lets
        , xLets
        , xLetsAnnot
        , splitXLets
        , splitXLetsAnnot
        , bindsOfLets
        , specBindsOfLets
        , valwitBindsOfLets

          -- ** Alternatives
        , patOfAlt
        , takeCtorNameOfAlt

          -- ** Patterns
        , bindsOfPat

          -- ** Casts
        , makeRuns

          -- ** Witnesses
        , wApp
        , wApps
        , annotOfWitness
        , takeXWitness
        , takeWAppsAsList
        , takePrimWiConApps

          -- ** Types
        , takeXType

          -- ** Data Constructors
        , xUnit, dcUnit
        , takeNameOfDaCon
        , takeTypeOfDaCon)
where
import DDC.Core.Exp.Annot.Exp
import DDC.Core.Exp.Annot.Compounds
import DDC.Core.Exp.Annot.Predicates
import DDC.Type.Exp.Simple.Compounds
import DDC.Type.Exp.Simple.Predicates
import DDC.Type.Exp
