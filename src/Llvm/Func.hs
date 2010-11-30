{-# OPTIONS -fwarn-unused-imports -fno-warn-type-defaults -cpp #-}
module Llvm.Func
	( funcDeclOfExp )
where

import DDC.Main.Error
import DDC.Sea.Exp
import DDC.Sea.Pretty

import Llvm
import Llvm.Runtime.Object
import Llvm.Util


stage = "Llvm.Stage"


funcDeclOfExp :: Exp a -> LlvmFunctionDecl
funcDeclOfExp (XVar (NSuper v) rt@(TPtr (TCon TyConObj)))
 = LlvmFunctionDecl {
	--  Unique identifier of the function
	decName = seaVar False v,
	--  LinkageType of the function
	funcLinkage = External,
	--  The calling convention of the function
	funcCc = CC_Ccc,
	--  Type of the returned value
	decReturnType = toLlvmType rt,
	--  Indicates if this function uses varargs
	decVarargs = FixedArgs,
	--  Parameter types and attributes
	decParams = [],
	--  Function align value, must be power of 2
	funcAlign = ptrAlign
	}

funcDeclOfExp (XVar (NSuper v) t@(TFun at rt))
 = LlvmFunctionDecl {
	decName = seaVar False v,
	funcLinkage = External,
	funcCc = CC_Ccc,
	decReturnType = toLlvmType rt,
	decVarargs = FixedArgs,
	decParams = map (\t -> (toLlvmType t, [])) at,
	funcAlign = ptrAlign
	}

funcDeclOfExp (XVar (NSuper v) rt@(TCon (TyConUnboxed _)))
 = LlvmFunctionDecl {
	decName = seaVar False v,
	funcLinkage = External,
	funcCc = CC_Ccc,
	decReturnType = toLlvmType rt,
	decVarargs = FixedArgs,
	decParams = [],
	funcAlign = ptrAlign
	}


funcDeclOfExp (XVar v t)
 = panic stage $ "funcDeclOfExp (" ++ show __LINE__ ++ ")\n\n"
	++ show v ++ "\n\n"
	++ show t ++ "\n"

