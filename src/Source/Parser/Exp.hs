{-# OPTIONS -O2 #-}

module Source.Parser.Exp
	( pExp, pExp1, pExpRHS
	, pStmt, pStmt_bind, pStmt_sig, pStmt_sigBind)
where

import Data.Maybe (isJust)
import Source.Exp
import Source.Parser.Type
import Source.Parser.Pattern
import Source.Parser.Base
import qualified Source.Token	as K

import qualified Shared.Var	as Var
import qualified Shared.VarPrim	as Var
import Shared.VarSpace		   (NameSpace(..))

import qualified Text.ParserCombinators.Parsec.Combinator	as Parsec
import qualified Text.ParserCombinators.Parsec.Prim		as Parsec

import Control.Monad

-- Expressions -------------------------------------------------------------------------------------

-- | Parse an expression
pExp :: Parser (Exp SP)
pExp
 = 	-- as while / when / unless are known to have two arguments
	--	we can relax the need to wrap the second one in parens

 	-- while ( EXP ) EXP  /  while EXP1 EXP
	do	tok	<- pTok K.While
		exp1	<-	do	g	<- pRParen pExp
			      		return	g
			<|> 	pExp1

		exp2	<- pExp
		return	$ XWhile (spTP tok) exp1 exp2

 <|>	-- when ( EXP ) EXP  /  when EXP1 EXP
	do	tok	<- pTok K.When
		exp1	<-	do	g	<- pRParen pExp
					return	g
			<|>	pExp1

		exp2	<- pExp
		return	$ XWhen (spTP tok) exp1 exp2

 <|>	-- unless ( EXP ) EXP  /  when EXP1 EXP
	do	tok	<- pTok K.Unless
		exp1	<-	do	g 	<- pRParen pExp
					return	g
			<|>	pExp1

		exp2	<- pExp
		return	$ XUnless (spTP tok) exp1 exp2


  	-- application
 <|>  	do 	exps@(x1 : _)	<- Parsec.many1 pExp2
		case exps of
		 [x]	-> return x
		 _	-> return $ XDefix (spX x1) exps
  <?>   "pExp"

pExp2 :: Parser (Exp SP)
pExp2
 = 	-- projections
 	-- EXP . EXP   /   EXP . (EXP)  /  EXP # EXP
 	(Parsec.try $ do
	 	exp	<- chainl1_either pExp1' pProj
 		return	$ stripXParens exp)

  <|>	do	exp	<- pExp1
		return	exp
  <?>   "pExp2"

-- | Parse an expression that can be used in an application
pExp1 :: Parser (Exp SP)
pExp1
 = do	exp	<- pExp1'
 	return	$ stripXParens exp

pExp1' :: Parser (Exp SP)
pExp1'
 =
	do	tok	<- pTok K.SBra
	  	exp	<- pListContents (spTP tok)
        	return	$ exp

  <|>	-- VAR & { TYPE }								-- NOT FINISHED
 	-- overlaps with VAR
	(Parsec.try $ do
		field	<- liftM vNameF (pQualified pVar)
		pTok K.And
		t	<- pCParen pType_body
		return	$ XProjT (spV field) t (JField (spV field) field))

  <|>	-- VAR/CON
	do	var	<- liftM vNameV (pQualified pVarCon)
		return	$ XVar (spV var) var

  <|>	-- VARFIELD					-- TODO: change this when we move to parsec
	do	var	<- liftM vNameF pVarField
		return	$ XObjField (spV var) var

  <|>	-- SYM
	do	sym	<- liftM vNameV pSymbol
		return	$ XOp (spV sym) sym

  <|>	-- `VAR`
  	do	pTok K.BackTick
		var	<- liftM vNameV (pQualified pVar)
		pTok K.BackTick
		return	$ XOp (spV var) var

  <|>	-- ()
  	do	tok	<- pTok K.Unit
		return	$ XVar (spTP tok) (Var.primUnit)

  <|>	-- lit
  	do	(lit, sp) <- pLiteralFmtSP
		return	$ XLit sp lit

  <|>	-- case EXP of { ALT .. }
  	do	tok	<- pTok K.Case
		exp	<- pExp
		pTok K.Of
		alts	<- pCParen (Parsec.sepEndBy1 pCaseAlt pSemis)
		return	$ XCase (spTP tok) exp alts

  <|>	-- match { ALT .. }
  	do	tok	<- pTok K.Match
		alts	<- pCParen (Parsec.sepEndBy1 pMatchAlt pSemis)
		return	$ XMatch (spTP tok) alts

  <|>	-- do { SIG/STMT/BIND .. }
	do	tok	<- pTok K.Do
		stmts	<- pCParen (Parsec.sepEndBy1 pStmt pSemis)
		return	$ XDo (spTP tok) stmts

  <|>	-- let { SIG/BIND .. } in EXP
  	do	tok	<- pTok K.Let
		binds	<- pCParen (Parsec.sepEndBy1 pStmt_sigBind pSemis)
		pTok K.In
		exp	<- pExp
		return	$ XLet (spTP tok) binds exp

  <|>	-- if EXP then EXP else EXP
	do	tok	<- pTok K.If
		exp1	<- pExp
		pTok K.Then
		exp2	<- pExp
		pTok K.Else
		exp3	<- pExp
		return	$ XIfThenElse (spTP tok) exp1 exp2 exp3

  <|>	-- \. VAR EXP ..
  	-- overlaps with next lambda forms
  	do	tok	<- pTok K.BackSlashDot
		var	<- liftM vNameF pVar
		exps	<- Parsec.many pExp1
		return	$ XLambdaProj (spTP tok) (JField (spTP tok) var) exps

  <|>	-- try EXP catch { ALT .. } (with { STMT; .. })
  	do	tok	<- pTok K.Try
		exp1	<- pExp
		pTok K.Catch
		alts	<- pCParen (Parsec.sepEndBy1 pCaseAlt pSemis)

		mWith	<-	Parsec.optionMaybe
                		(do	pTok K.With
					stmts	<- pCParen (Parsec.sepEndBy1 pStmt pSemis)
				 	return	$ (XDo (spTP tok) stmts))

		return	$ XTry (spTP tok) exp1 alts mWith

  <|>	-- throw EXP							-- TODO: this could be a regular function call
  	do	tok	<- pTok K.Throw
		exp	<- pExp
		return	$ XThrow (spTP tok) exp

  <|>	-- break
  	do	tok	<- pTok K.Break					-- TODO: this could be a regular function call
		return	$ XBreak (spTP tok)

  <|>	do	tok	<- pTok K.BackSlash
  		exp	<- pBackslashExp (spTP tok)
                return	$ exp

  <|>	-- Starts with a K.RBra.
	do	tok	<- pTok K.RBra
  		exp1	<- pExp
		expr	<- pBracketExp (spTP tok) exp1
		return 	$ expr

  <?>   "pExp1'"


pBracketExp :: SP -> Exp SP -> Parser (Exp SP)
pBracketExp startPos exp1 =
	do	pTok K.Comma
		exps	<- Parsec.sepBy1 pExp (pTok K.Comma)
		pTok K.RKet
		return	$ XTuple startPos (exp1 : exps)

  <|>	do	pTok K.RKet
		return 	$ XParens startPos exp1


pBackslashExp :: SP -> Parser (Exp SP)
pBackslashExp startPos =
	do	pTok K.Case
		alts	<- pCParen (Parsec.sepEndBy1 pCaseAlt pSemis)
		return	$ XLambdaCase startPos alts

  <|>	do	pats	<- Parsec.many1 pPat1
		pTok	<- pTok K.RightArrow
		exp	<- pExp
		return	$ XLambdaPats startPos pats exp


pListContents :: SP -> Parser (Exp SP)
pListContents startPos =
	-- Empty list.
	do	pTok K.SKet
  		return $ XList startPos []

  <|>	-- Either a list, a list comprehension
  	do	first	<- pExp
	        exp	<- pListContentsHaveOne startPos first
		return $ exp

  <?>	"pListContents"

pListContentsHaveOne :: SP -> Exp SP -> Parser (Exp SP)
pListContentsHaveOne startPos first =
	-- Single element list.
	do	pTok K.SKet
  		return $ XList startPos [first]

  <|>	-- List comprehension.
	do	pTok K.Bar
		quals	<- Parsec.sepBy1 pLCQual (pTok K.Comma)
		pTok K.SKet
		return	$ XListComp startPos first quals

  <|>	-- Have range expression without step.
	do	pTok K.DotDot
        	exp <- pListRangeOne startPos first
                return exp

  <|>	-- Have one element and Comma
	do	pTok K.Comma
        	second	<- pExp
	        exp	<- pListContentsHaveTwo startPos first second
		return exp

  <?>	"pListContentsHaveOne"

pListRangeOne :: SP -> Exp SP -> Parser (Exp SP)
pListRangeOne startPos first =
	do	pTok K.SKet
		return $ XListRange startPos True first Nothing Nothing

  <|>	do	exp <- pExp
		pTok K.SKet
		return $ XListRange startPos False first Nothing (Just exp)

  <?>	"pListRangeOne"


pListContentsHaveTwo :: SP -> Exp SP -> Exp SP -> Parser (Exp SP)
pListContentsHaveTwo startPos first second =
	do	pTok K.DotDot
		exp <- pListRangeTwo startPos first second
		return $ exp

  <|>	do	pTok K.SKet
		return $ XList startPos [first, second]

  <|>	do	pTok K.Comma
  		rest <- Parsec.sepBy1 pExp (pTok K.Comma)
		pTok K.SKet
		return $ XList startPos (first : second : rest)

  <?>	"pListContentsHaveTwo"

pListRangeTwo :: SP -> Exp SP -> Exp SP -> Parser (Exp SP)
pListRangeTwo startPos first second =
	do	pTok K.SKet
		return $ XListRange startPos True first (Just second) Nothing

  <|>	do	exp <- pExp
		pTok K.SKet
		return $ XListRange startPos False first (Just second) (Just exp)

  <?>	"pListRangeTwo"


-- | Parse an expression in the RHS of a binding or case/match alternative
--	these can have where expressions on the end
pExpRHS :: Parser (Exp SP)
pExpRHS
 = do 	exp	<- pExp
	mWhere	<- Parsec.optionMaybe
        		(do 	tok 	<- pTok K.Where
				stmts	<- pCParen $ Parsec.sepEndBy1 pStmt_sigBind pSemis
				return	$ (tok, stmts))

	case mWhere of
		Nothing			-> return $ exp
		Just (tok, stmts)	-> return $ XWhere (spTP tok) exp stmts


-- | Parse a projection operator
pProj :: Parser (Exp SP -> Exp SP -> Either String (Exp SP))
pProj
 = 	do	pTok K.Dot
	 	return	(makeProjV JField JIndex)

 <|>	do	pTok K.Hash
 		return	(makeProjV JFieldR JIndexR)
 <?> "pProj"

makeProjV fun funIndex x y
	| XVar sp v	<- y
	= Right $ XProj (spX x) (stripXParens x)
		$ fun 	sp
			v { Var.nameSpace = NameField }

	| XParens sp y'	<- y
	= Right $ XProj (spX x) (stripXParens x)
		$ funIndex
			sp
			(stripXParens y')


	| otherwise
	= Left "pProj: LHS is not a field"

stripXParens (XParens _ x)	= stripXParens x
stripXParens xx			= xx


-- | Parse a list comprehension production / qualifier / guard
pLCQual :: Parser (LCQual SP)
pLCQual =
 	-- PAT <- EXP
 	-- overlaps with let and guard
 	(Parsec.try $ do
        	pat	<- pPat
        	lazy	<- pLeftArrowIsLazy
		exp	<- pExp
		return	$ LCGen lazy pat exp)

  <|>	do	exp	<- pExp
  		return	$ LCExp exp

  <?>   "pLCQual"

pLeftArrowIsLazy :: Parser Bool
pLeftArrowIsLazy =
	do	pTok K.LeftArrowLazy
        	return True

  <|>	do	pTok K.LeftArrow
  		return False


-- Alternatives ------------------------------------------------------------------------------------

-- | Parse a case style alternative
pCaseAlt :: Parser (Alt SP)						-- NOT finished, guards in alts |
pCaseAlt
 = 	-- PAT -> EXP
   do	pat	<- pPat
 	pTok K.RightArrow
	exp	<- pExpRHS
	return	$ APat (spW pat) pat exp


-- | Parse a match style alternative
pMatchAlt :: Parser (Alt SP)
pMatchAlt
 =	-- \| GUARD, ... = EXP
   	do	tok	<- pTok K.Bar
	   	guards	<- (Parsec.sepBy1 pGuard (pTok K.Comma))
		pTok K.Equals
		exp	<- pExpRHS
		return	$ AAlt (spTP tok) guards exp

  <|>	-- \= EXP
  	do	tok	<- pTok K.GuardDefault
		exp	<- pExpRHS
		return	$ ADefault (spTP tok) exp

  <?>   "pMatchAlt"

-- | Parse a guard
pGuard :: Parser (Guard SP)
pGuard
 = 	-- PAT <- EXP
 	-- overlaps with EXP
	(Parsec.try $ do
		pat	<- pPat
	 	pTok K.LeftArrow
		exp	<- pExpRHS
		return	$ GExp (spW pat) pat exp)

	-- EXP
 <|>	do	exp	<- pExpRHS
 		return	$ GBool (spX exp) exp
 <?>   "pGuard"


-- Statements --------------------------------------------------------------------------------------

-- | Parse a signature, statement or binding
pStmt :: Parser (Stmt SP)
pStmt
 = 	-- bindings overlap with expressions
 	(Parsec.try pStmt_sigBind)

  <|>	do	exp	<- pExpRHS
  		return	$ SStmt (spX exp) exp
  <?>   "pStmt"


-- | Parse a bind (only)
pStmt_bind :: Parser (Stmt SP)
pStmt_bind
 = 	-- VAR PAT .. | ALT ..
	-- overlaps with regular binding
 	(Parsec.try $ do
 		var	<- liftM vNameV $ pVar
		pats	<- Parsec.many pPat1
		alts	<- Parsec.many1 pMatchAlt
		return	$ SBindFun (spV var) var pats alts)

	-- VAR PAT = EXPRHS
 <|>	(Parsec.try $ do
 		var	<- liftM vNameV $ pVar
		pats	<- Parsec.many pPat1
		pTok K.Equals
		exp	<- pExpRHS
		return	$ SBindFun (spV var) var pats [ADefault (spV var) exp])

	-- PAT	<- EXPRHS
 <|>	(Parsec.try $ do
 		pat	<- pPat
		pTok K.LeftArrow
		exp	<- pExpRHS
		return	$ SBindMonadic (spW pat) pat exp)

 <|>	-- PAT | ALT ..
 	(Parsec.try $ do
		pat	<- pPat
		alts	<- Parsec.many1 pMatchAlt
		return	$ SBindPat (spW pat) pat (XMatch (spW pat) alts))

 <|>	-- PAT  = EXPRHS
 	do	pat	<- pPat
		pTok K.Equals
		exp	<- pExpRHS
		return	$ SBindPat (spW pat) pat exp

 <?>	"pStmt_bind"


-- | Parse a type sig (only)
pStmt_sig :: Parser (Stmt SP)
pStmt_sig
 = do	vars	<- Parsec.sepBy1 pVar (pTok K.Comma)
	let vars' = map vNameV vars
 	ht	<- pTok K.HasType
	typ	<- pType
	return	$ SSig (spTP ht) vars' typ

-- | Parse a signature or binding
pStmt_sigBind :: Parser (Stmt SP)
pStmt_sigBind
 = 	(Parsec.try pStmt_sig)
  <|> 	pStmt_bind
  <?>   "pStmt_sigBind"

