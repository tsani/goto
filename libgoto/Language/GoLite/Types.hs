{-|
Module      : Language.GoLite.Types
Description : Type definitions for the internal representation of GoLite code
Copyright   : (c) Jacob Errington and Frederic Lafrance, 2016
License     : MIT
Maintainer  : goto@mail.jerrington.me
Stability   : experimental

Defines the core types used in the internal representation of GoLite code.
-}

{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE ViewPatterns #-}

module Language.GoLite.Types
( -- * Global identifiers in GoLite
  GlobalId
, Gid.DataOrigin(..)
, Gid.gidNum
, Gid.gidOrigName
, Gid.gidTy
, Gid.gidOrigin
  -- * Symbols
, SymbolInfo'(..)
, SymbolInfo
, SymbolKind
, variableKind
, typeKind
, SymbolLocation(..)
  -- * The GoLite type system
, GoTypeF(..)
, Type
, BuiltinType(..)
  -- ** Miscellaneous type functions
, unalias
, defaultType
  -- ** Predicates on types
, isAliasType
, isSliceType
, isReferenceType
, isNilType
, isFuncType
, isBuiltinType
, isAllowedInExprStmt
, isUntyped
, isOrdered
, isIntegral
, isString
, isConvertible
, isComparable
, isArithmetic
, isLogical
, isValue
, isPrintable
  -- ** Constructors for types
  -- *** Complex types
, arrayType
, sliceType
, funcType
, structType
, aliasType
  -- *** Basic types
, nilType
, builtinType
, voidType
, intType
, untypedIntType
, typedIntType
, runeType
, untypedRuneType
, typedRuneType
, stringType
, untypedStringType
, typedStringType
, boolType
, untypedBoolType
, typedBoolType
, floatType
, untypedFloatType
, typedFloatType
  -- *** Special types
, unknownType
, typeSum
  -- * Scoping and symbol manipulation
, Scope(..)
, SymbolName
, Symbol -- abstract so people can't build (NamedSymbol "_")
, symbolFromString
, stringFromSymbol
, maybeSymbol
, blankSymbol
) where

import qualified Language.Common.GlobalId as Gid
import Language.GoLite.Pretty
import Language.GoLite.Syntax.SrcAnn
import qualified Language.GoLite.Syntax.Types as T

import Data.Functor.Foldable
import qualified Data.Map as M
import Data.String

-- | A GoLite global identifier tracks GoLite type information as well as the
-- original name and location of the identifier that is replaced.
type GlobalId = Gid.GlobalId Type (SrcAnn Symbol ())

instance Pretty GlobalId where
    pretty (Gid.GlobalId
        { Gid.gidOrigName = Ann _ s
        , Gid.gidNum = n
        }) = pretty s <> text "_" <> int n

-- | An entry in the symbol table.
data SymbolInfo' loc ty gid
    -- | A symbol in scope.
    = VariableInfo
        { symLocation :: !loc
        -- ^ The location of the symbol's definition.
        , symType :: !ty
        -- ^ The canonical type of the symbol.
        , symGid :: !gid
        }
    | TypeInfo
        { symLocation :: !loc
        -- ^ The location of the symbol's definition.
        , symType :: !ty
        -- ^ The canonical type of the symbol.
        }
    deriving (Eq, Ord, Show)

type SymbolInfo = SymbolInfo' SymbolLocation Type GlobalId

instance Pretty SymbolInfo where
    pretty sym =
        prettyBrackets True (pretty (symLocation sym))
        <+> nest indentLevel (pretty $ symType sym)

-- | 'SymbolInfo' but with no real data inside, leaving essentially only the
-- constructors.
type SymbolKind = SymbolInfo' () () ()

variableKind :: SymbolKind
variableKind = VariableInfo () () ()

typeKind :: SymbolKind
typeKind = TypeInfo () ()

-- | The location of a symbol.
data SymbolLocation
    -- | The symbol is built-in to the compiler.
    = Builtin
    -- | The symbol is in a source file.
    | SourcePosition !SrcSpan
    deriving (Eq, Ord, Show)

instance Pretty SymbolLocation where
    pretty sym = case sym of
        Builtin -> text "<universe>"
        SourcePosition s ->
            let start = srcStart s in
            let name = text (sourceName start) in
            let column = int (sourceColumn start) in
            let line = int (sourceLine start) in
            name <> colon <> line <> colon <> column <> colon

-- | The base functor for a canonical representation of a GoLite type.
data GoTypeF f
    -- | The built-in void type.
    = VoidType
    -- | The built-in integer number type.
    | IntType
        { constantIsTyped :: Bool
        }
    -- | The built-in unicode character type.
    | RuneType
        { constantIsTyped :: Bool
        }
    -- | The built-in string type.
    | StringType
        { constantIsTyped :: Bool
        }
    -- | The built-in floating point number type.
    | FloatType
        { constantIsTyped :: Bool
        }
    -- | The built-in boolean type.
    | BoolType
        { constantIsTyped :: Bool
        }
    -- | A statically-sized array of some type.
    | Array Int f
    -- | A slice of some type.
    | Slice f
    -- | A struct type.
    | Struct
        { structTypeFields :: [(SrcAnn Symbol (), f)]
        }
    -- | The type for the predeclared identifier "nil". No other expression has
    -- this type.
    | NilType
    -- | Types for built-in functions, which are unrepresentable in the go
    -- typesystem.
    | BuiltinType BuiltinType
    -- | An alias for another type.
    | AliasType SrcAnnIdent f
    -- | The internal unknown type is used as the type of undeclared
    -- identifiers.
    | UnknownType
    -- | The type of a function.
    | FuncType
        { funcTypeArgs :: [(SrcAnn Symbol (), f)]
        , funcTypeRet :: f
        }
    -- | Multiple types. Used to report errors about polymorphic built-ins that
    -- can take multiple types.
    | TypeSum [f]
    deriving (Eq, Functor, Ord, Show)

-- | A canonical representation of a GoLite type.
type Type = Fix GoTypeF

instance Pretty Type where
    pretty = cata f where
        f :: GoTypeF Doc -> Doc
        f t = case t of
            VoidType -> text "void"
            IntType b -> text "int" <+> if b then empty else text "(untyped)"
            RuneType b -> text "rune" <+> if b then empty else text "(untyped)"
            StringType b -> text "string" <+> if b then empty else text "(untyped)"
            FloatType b -> text "float" <+> if b then empty else text "(untyped)"
            BoolType b -> text "bool" <+> if b then empty else text "(untyped)"
            NilType -> text "nil"
            UnknownType -> text "_ty_unknown"
            AliasType (Ann _ (T.Ident alias)) t' ->
                prettyParens True (text alias <+> text "->" <+> t')
            BuiltinType b -> pretty b
            Array n t' -> prettyBrackets True (pretty n) <> t'
            Slice t' -> prettyBrackets True empty <> t'
            Struct fields ->
                text "struct {" $+$ nest indentLevel (
                    vcat (map (\(sym, t') -> pretty sym <+> t' <> text ";") fields)
                )
                $+$
                text "}"
            FuncType
                { funcTypeArgs = args
                , funcTypeRet = rt
                } ->
                text "func" <> prettyParens True (
                    hsep (punctuate comma (map (pretty . snd) args))
                ) <+>
                pretty rt
            -- Those two degenerate cases for TypeSum should hopefully not occur
            TypeSum [] -> empty
            TypeSum [x] -> pretty x
            -- "Intended" use for TypeSum
            TypeSum xs -> hsep (punctuate comma (map pretty $ init xs))
                            <+> text "or"
                            <+> (pretty $ last xs)

-- | The types of builtins.
data BuiltinType
    -- | The type of the @append@ builtin.
    = AppendType
    -- | The type of the @cap@ builtin.
    | CapType
    -- | The type of the @copy@ builtin.
    | CopyType
    -- | The type of the @len@ builtin.
    | LenType
    -- | The type of the @make@ builtin.
    | MakeType
    deriving (Eq, Ord, Read, Show)

instance Pretty BuiltinType where
    pretty b = case b of
        AppendType -> text "_ty_append"
        CapType -> text "_ty_cap"
        CopyType -> text "_ty_copy"
        LenType -> text "_ty_len"
        MakeType -> text "_ty_make"

-- | Tunnels down 'AliasType' constructors in a type to get the underlying type
-- of a named type.
--
-- /Remark/: this does not remove all aliases from the type! It only removes
-- aliases top down until a non-alias type is reached.
--
-- This function is idempotent.
--
-- > unalias . unalias = unalias
unalias :: Type -> Type
unalias (Fix t) = case t of
    AliasType _ t' -> unalias t'
    _ -> Fix t

-- | Determines the default type of untyped types.
--
-- This function is idempotent.
-- > defaultType . defaultType = defaultType
defaultType :: Type -> Type
defaultType (Fix t) = Fix $ case t of
    IntType False -> IntType True
    RuneType False -> RuneType True
    StringType False -> StringType True
    FloatType False -> FloatType True
    BoolType False -> BoolType True
    _ -> t

-- | Decides whether a type is a named type.
isAliasType :: Type -> Bool
isAliasType (Fix UnknownType) = True
isAliasType t = t /= unalias t

-- | Determines whether a type is a slice type.
isSliceType :: Type -> Bool
isSliceType (unalias -> Fix t) = case t of
    UnknownType -> True
    Slice _ -> True
    _ -> False

-- | Decides whether a type is a reference type, i.e. admits the value @nil@.
isReferenceType :: Type -> Bool
isReferenceType (unalias -> Fix t) = case t of
    Slice _ -> True
    FuncType _ _ -> True
    UnknownType -> True
    _ -> False

-- | Decides whether a type is the built-in 'NilType'.
isNilType :: Type -> Bool
isNilType (Fix t) = case t of
    NilType -> True
    UnknownType -> True
    _ -> False

-- | Decides whether a type is a function type.
isFuncType :: Type -> Bool
isFuncType (Fix t) = case t of
    FuncType _ _ -> True
    UnknownType -> True
    _ -> False

-- | Decides whether a type is one of the builtin types
isBuiltinType :: Type -> Bool
isBuiltinType (Fix t) = case t of
    BuiltinType _ -> True
    UnknownType -> True
    _ -> False

-- | Decides whether a type is allowed as a function call in expression statement
-- context. Only the builtins @append@, @cap@, @len@ and @make@ are not allowed
-- in that context.
isAllowedInExprStmt :: Type -> Bool
isAllowedInExprStmt (Fix t) = case t of
    BuiltinType AppendType -> False
    BuiltinType CapType -> False
    BuiltinType LenType -> False
    BuiltinType MakeType -> False
    UnknownType -> True
    _ -> True

-- | Decides whether the type is of an untyped constant.
isUntyped :: Type -> Bool
isUntyped (Fix t) = case t of
    IntType False -> True
    RuneType False -> True
    StringType False -> True
    FloatType False -> True
    BoolType False -> True
    UnknownType -> True
    _ -> False

-- | Decides whether a type is ordered. All basic types except boolean are
-- ordered. No other type is ordered. Ordered types can be compared using
-- the order operators @<@, @>@, @>=@ and @<=@.
isOrdered :: Type -> Bool
isOrdered (unalias -> Fix t) = case t of
    IntType _ -> True
    FloatType _ -> True
    RuneType _ -> True
    StringType _-> True
    UnknownType -> True
    _ -> False

-- | Tests whether a type is integral. Ints and runes are integral (both the
-- typed and untyped versions). No other type is integral.
isIntegral :: Type -> Bool
isIntegral (unalias -> Fix t) = case t of
    IntType _ -> True
    RuneType _ -> True
    UnknownType -> True
    _ -> False

-- | Tests whether a type is a typed or untyped string. Necessary for checking
-- addition operations.
isString :: Type -> Bool
isString (unalias -> Fix t) = case t of
    StringType _ -> True
    UnknownType -> True
    _ -> False

-- | Types that can all be casted one to the other.
isConvertible :: Type -> Bool
isConvertible (unalias -> Fix t) = case t of
    IntType _ -> True
    RuneType _ -> True
    FloatType _ -> True
    BoolType _ -> True
    UnknownType -> True
    _ -> False

{- | Decides whether two types are comparable. Types are comparable iff their
   default types are identical, except in the following cases:

      * Slice types are not comparable to each other.
      * Slice types can be compared to nil.
      * Array types are comparable if their inner types are comparable and they
        have the same length.

   Comparable types can be tested for equality or inequality using @==@ and
   @!=@.

  In the absence of 'UnknownType', this function is commutative.

  > isComparable = flip . isComparable
-}
isComparable :: Type -> Type -> Bool
isComparable (defaultType -> Fix t) (defaultType -> Fix u) = case (t, u) of
    (Slice _, Slice _) -> False
    (Slice _, NilType) -> True
    (NilType, Slice _) -> True
    (Array m t', Array n u') -> m == n && t' `isComparable` u'
    (Struct ts, Struct us) -> and $
                                map (\((i, t'), (i', u')) ->
                                        bare i == bare i'
                                    &&  t' `isComparable` u')
                                    (zip ts us)
    (UnknownType, _) -> True
    (_, UnknownType) -> True
    (_, _)-> t == u

-- | Decides whether a type is arithmetic. An arithmetic type can have
-- arithmetic operations (addition, multiplication, etc.) applied to it.
-- The types int, float and rune are arithmetic. No other type is arithmetic.
isArithmetic :: Type -> Bool
isArithmetic (unalias -> Fix t) = case t of
    IntType _ -> True
    FloatType _ -> True
    RuneType _ -> True
    UnknownType -> True
    _ -> False

-- | Determines whether a type is logical (basically a boolean). Logical types
-- can have logical operators applied to them (@&&@, @||@, @!@)
isLogical :: Type -> Bool
isLogical (unalias -> Fix t) = case t of
    BoolType _ -> True
    UnknownType -> True
    _ -> False

-- | Determines whether a type can be used as a value. Non-value types are
-- disallowed in contexts where a value of any type is allowed. Those are:
--      * Variable declarations with no type
--      * Switch expressions
isValue :: Type -> Bool
isValue (unalias -> Fix t) = case t of
    BuiltinType _ -> False
    FuncType _ _ -> False
    NilType -> False
    TypeSum _ -> False -- Shouldn't occur, but just for completeness' sake.
    VoidType -> False
    UnknownType -> True
    _ -> True

-- | Determines whether a type is printable. This is *almost* like isValue,
-- except that additionally we can't print structs or arrays (??), but we CAN
-- print function values (??!??!?)
isPrintable :: Type -> Bool
isPrintable (unalias -> Fix t) = case t of
    BuiltinType _ -> False
    NilType -> False
    TypeSum _ -> False -- Shouldn't occur, but just for completeness' sake.
    VoidType -> False
    Struct _ -> False
    Array _ _ -> False
    Slice _ -> False
    UnknownType -> True
    _ -> True

builtinType :: BuiltinType -> Type
builtinType = Fix . BuiltinType

voidType :: Type
voidType = Fix VoidType

intType :: Bool -> Type
intType = Fix . IntType

untypedIntType :: Type
untypedIntType = intType False

typedIntType :: Type
typedIntType = intType True

runeType :: Bool -> Type
runeType = Fix . RuneType

untypedRuneType :: Type
untypedRuneType = runeType False

typedRuneType :: Type
typedRuneType = runeType True

stringType :: Bool -> Type
stringType = Fix . StringType

untypedStringType :: Type
untypedStringType = stringType False

typedStringType :: Type
typedStringType = stringType True

floatType :: Bool -> Type
floatType = Fix . FloatType

untypedFloatType :: Type
untypedFloatType = floatType False

typedFloatType :: Type
typedFloatType = floatType True

boolType :: Bool -> Type
boolType = Fix . BoolType

untypedBoolType :: Type
untypedBoolType = boolType False

typedBoolType :: Type
typedBoolType = boolType True

arrayType :: Int -> Type -> Type
arrayType n t = Fix $ Array n t

sliceType :: Type -> Type
sliceType = Fix . Slice

nilType :: Type
nilType = Fix NilType

funcType :: [(SrcAnn Symbol (), Type)] -> Type -> Type
funcType args ret = Fix $ FuncType
    { funcTypeArgs = args
    , funcTypeRet = ret
    }

unknownType :: Type
unknownType = Fix UnknownType

structType :: [(SrcAnn Symbol (), Type)] -> Type
structType = Fix . Struct

aliasType :: SrcAnnIdent -> Type -> Type
aliasType i = Fix . AliasType i

typeSum :: [Type] -> Type
typeSum = Fix . TypeSum

-- | The name of a symbol is simply the string assigned to it by the
-- programmer.
type SymbolName = String

-- | Scopes track definitions of symbols.
data Scope
    = Scope
        { scopeMap :: M.Map SymbolName SymbolInfo
        }
    deriving (Eq, Ord, Show)

instance Pretty Scope where
    pretty s
        = vcat $ map
            (\(n, s') -> text (n ++ "->") <+> pretty s')
            (M.assocs $ scopeMap s)

-- | A more structured version of 'Ident'.
data Symbol a
    = NamedSymbol SymbolName
    -- ^ A named symbol.
    | Blank
    -- ^ The blank identifier.
    deriving (Eq, Functor, Ord, Read, Show)

instance Pretty (Symbol a) where
    pretty s = case s of
        NamedSymbol name -> text name
        Blank -> text "_"

-- | Creates 'NamedSymbol's.
instance IsString (Symbol a) where
    fromString = NamedSymbol

-- | Converts a raw identifier into a symbol.
symbolFromString :: String -> Symbol a
symbolFromString s
    | s == "_" = Blank
    | otherwise = NamedSymbol s

stringFromSymbol :: Symbol a -> String
stringFromSymbol s = case s of
    Blank -> "_"
    NamedSymbol name -> name

-- | 'Symbol' @a@ is isomorphic to 'Maybe' @String@; this function performs
-- that conversion.
maybeSymbol :: Symbol a -> Maybe String
maybeSymbol s = case s of
    Blank -> Nothing
    NamedSymbol name -> Just name

blankSymbol :: Symbol a
blankSymbol = Blank
