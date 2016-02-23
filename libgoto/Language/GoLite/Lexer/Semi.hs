{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Language.GoLite.Lexer.Semi
( -- * Semicolon handling
  Semi() -- abstract !
, SemiError(..)
  -- ** Semi introduction
, withDetectSemicolon
, withDetectExplicitSemicolon
  -- ** Semi elimination
, requireSemi
, requireSemiP
, noSemi
, noSemiP
, unSemi
, unSemiP
, condUnSemiP
  -- ** Semi-based parsers
, semicolon
, semisym
, explicitSemisym
, semiList
) where

import Language.GoLite.Lexer.Core

import Control.Monad.State
import Control.Monad.Except
import Data.Maybe ( isJust )

-- | Errors that can arise during semicolon handling.
data SemiError
    = UnexpectedSemicolon
    | ExpectedSemicolon
    | NoSemicolonDetection

-- | Represent explicit or implicit semicolons.
--
-- Parsers that parse values wrapped in "Semi" will detect implicit or explicit
-- semicolons. They do so with the `withDetectSemicolon` combinator.
newtype Semi a
    = Semi { runSemi :: StateT (Maybe Bool) (Except SemiError) a }
    deriving
        ( Functor
        , Applicative
        , Monad
        , MonadState (Maybe Bool)
        , MonadError SemiError
        )

-- | Runs a computation in the "Semi" monad, requiring that there be a
-- semicolon. Exceptions from the "Semi" monad are reinterpreted as parse
-- errors, and the presence of a semicolon will cause an \"expected ; or
-- newline\" parser failure.
requireSemiP :: Semi a -> Parser a
requireSemiP s = case runExcept $ runStateT (runSemi s) Nothing of
    Left UnexpectedSemicolon ->
        failure [Unexpected ";", Unexpected "newline"]

    Left ExpectedSemicolon ->
        failure [Expected ";", Expected "newline"]

    Left NoSemicolonDetection ->
        failure [Message "No semicolon detection performed!"]

    Right e -> case e of
        (_, Nothing) -> failure [Message "No semicolon detection performed!"]
        (x, Just True) -> pure x
        (_, Just False) -> failure [Expected ";", Expected "newline"]

-- | Analyzes the current state of the "Semi" monad and throws errors if no
-- semicolon is present.
requireSemi :: Semi ()
requireSemi = do
    isSemiM <- get
    case isSemiM of
        Nothing -> throwError NoSemicolonDetection
        Just True -> pure ()
        Just False -> throwError ExpectedSemicolon

-- | Runs a computation in the "Semi" monad, requiring that there be no
-- semicolon. Exceptions from the "Semi" monad are reinterpreted as parse
-- errors, and the presence of a semicolon will cause an \"unexpected ; or
-- newline\" parser failure.
noSemiP :: Semi a -> Parser a
noSemiP s = case runExcept $ runStateT (runSemi s) Nothing of
    Left UnexpectedSemicolon ->
        failure [Unexpected ";", Unexpected "newline"]

    Left ExpectedSemicolon ->
        failure [Expected ";", Expected "newline"]

    Left NoSemicolonDetection ->
        failure [Message "No semicolon detection performed!"]

    Right e -> case e of
        (_, Nothing) -> failure [Message "No semicolon detection performed!"]
        (x, Just False) -> pure x
        (_, Just True) -> unexpected "ohhh nooo ;"

-- | Analyzes the current state of the "Semi" monad and throws errors if no
-- semicolon detection has been performed or if there is a semicolon present.
noSemi :: Semi ()
noSemi = do
    isSemiM <- get
    case isSemiM of
        Nothing -> throwError NoSemicolonDetection
        Just True -> throwError UnexpectedSemicolon
        Just False -> pure ()

-- | Runs a computation in the "Semi" monad, extracting the parse result or the
-- error if any.
unSemi :: Semi a -> Either SemiError a
unSemi s = runExcept $ evalStateT (runSemi s) Nothing

-- | Runs a computation in the "Semi" monad, returning the parse result in the
-- "Parser" monad or reinterpreting the error as a parse error if any.
--
-- Implemented in terms of "condUnSemiP".
unSemiP :: Semi a -> Parser a
unSemiP s = condUnSemiP s (\_ -> True) ""

-- | Runs a computation in the "Semi" monad. Semi errors are reinterpreted as
-- Parser errors. If the computation succeeds, applies a predicate to the
-- result. If the predicate passes, the result is returned in the Parser monad;
-- otherwise, a parse error with the given message is raised.
condUnSemiP :: Semi a -> (a -> Bool) -> String -> Parser a
condUnSemiP s p m = case unSemi s of
    Left UnexpectedSemicolon ->
        failure [Unexpected ";", Unexpected "newline"]

    Left ExpectedSemicolon ->
        failure [Expected ";", Expected "newline"]

    Left NoSemicolonDetection ->
        failure [Message "No semicolon detection performed!"]

    Right x -> if p x then pure x else failure [Message m]

-- | Consumes whitespace until reaching the end of line/file.
eventuallyEol :: Parser ()
eventuallyEol = hidden $ void $ manyTill spaceChar (void eol <|> eof)

-- | Performs a semicolon detection.
detectSemicolon :: Parser Bool
detectSemicolon = isJust <$> optional (semicolon <|> try eventuallyEol)

-- | Runs a parser and performs an explicit semicolon detection, introducing a
-- computation in the "Semi" monad. The difference with `withDetectSemicolon`
-- is that this does not check for end-of-lines, so it is used in conjunction
-- with tokens that do not trigger semicolon insertion (e.g. some keywords).
withDetectExplicitSemicolon :: Parser a -> Parser (Semi a)
withDetectExplicitSemicolon p = do
    q <- p
    t <- isJust <$> optional semicolon
    pure $ do
        put (Just t)
        pure q

-- | Runs a parser and performs a semicolon detection, introducing a
-- computation in the "Semi" monad.
withDetectSemicolon :: Parser a -> Parser (Semi a)
withDetectSemicolon p = do
    q <- p
    t <- detectSemicolon
    pure $ do
        put (Just t)
        pure q

-- | Parses a semicolon symbol \";\".
semicolon :: Parser ()
semicolon = symbol_ ";"

-- | Parses a string and performs semicolon detection.
semisym :: String -> Parser (Semi String)
semisym = withDetectSemicolon . symbol

-- | Parses a string and performs explicit semicolon detection.
explicitSemisym :: String -> Parser (Semi String)
explicitSemisym = withDetectExplicitSemicolon . symbol

-- | Transforms a parser producing a list of Semi elements into a parser
-- producing a Semi list of elements, with potentially different semicolon
-- checks for the last element versus the rest of the list.
semiList :: Parser ([Semi a]) -> Semi () -> Semi () -> Parser (Semi [a])
semiList p internal end = do
    s <- p
    pure $ foldr (\cur acc -> do
                    acc' <- acc
                    cur' <- cur
                    case acc' of
                            [] -> end
                            _ -> internal
                    pure $ cur':acc') (pure []) s