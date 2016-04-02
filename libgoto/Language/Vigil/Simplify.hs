{-|
Module      : Language.Vigil.Simplify
Description : Definition of the Simplify monad
Copyright   : (c) Jacob Errington and Frederic Lafrance, 2016
License     : MIT
Maintainer  : goto@mail.jerrington.me
Stability   : experimental

Defines the @Simplify@ monad as an instance of
'Language.GoLite.Monad.Traverse.MonadTraversal'. Its purpose is to build a
Vigil syntax tree from a type-and-source annotated GoLite syntax tree.
-}

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeFamilies #-}

module Language.Vigil.Simplify where

import Data.Void ( Void )

import Language.Common.Monad.Traverse
import Language.Vigil.Syntax
import Language.Vigil.Syntax.Basic

-- | The @Simplify@ monad is a traversal that cannot throw errors, and uses an
-- internal state to keep track of the simplification process.
newtype Simplify a
    = Simplify { unSimplify :: Traversal SimplificationError SimplifyState a }
    deriving
        ( Functor
        , Applicative
        , Monad
        , MonadError SimplificationError
        , MonadState SimplifyState
        )

instance MonadTraversal Simplify where
    -- Fred: right now I can't think of any errors that would occur during simplification
    type TraversalError Simplify = Void
    type TraversalState Simplify = SimplifyState
    type TraversalException Simplify = SimplificationError

    reportError = error "unimplemented"

    getErrors = error "unimplemented"

-- | Generate a fresh temporary name.
makeTemp :: a -> Simplify BasicIdent
makeTemp _ = do
    num <- gets currentTemp
    let i = "%tmp" ++ (show num)
    modify (\s -> s { currentTemp = currentTemp s + 1 })
    return $ Ident i


data SimplifyState
    = SimplifyState -- More will be added later on.
        { currentTemp :: Int
        -- ^ Indicates the number of the next autogenerated temporary identifier.
        , newDeclarations :: [BasicIdent]
        -- ^ What temporaries have been declared so far in the current function.
        }

data SimplificationError
    = InvariantViolation String