import Data.List
import Data.List.Split
import Data.Char
import System.Environment
import System.Directory
import System.IO

type Symbol = String
type Rule = (Symbol, [Symbol])
type NSet = (Symbol, [Symbol])

instance Show Grammar where show = showGrammar

data Grammar = Grammar {
    nterms :: [Symbol],
    terms :: [Symbol],
    start :: Symbol,
    rules :: [Rule]
}

showGrammar :: Grammar -> String
showGrammar g = intercalate "\n" [
    (intercalate "," (nterms g)),
    (intercalate "," (terms g)),
    (start g),
    intercalate "\n" (map (\x -> fst x ++ "->" ++ (concat $ snd x)) (rules g))
    ]

-- creates grammar and checks that its input format
-- is used when reading input data
newGrammar :: [Symbol] -> [Symbol] -> Symbol -> [Rule] -> Grammar
newGrammar nts ts start rs
    | not (all isUpper $ concat nts) = error "wrong input format of the non-terminals"
    | not (all isLower $ concat ts) = error "wrong input format of the terminals"
    | not (start `elem` nts) = error "wrong input format, unknown starting symbol"
    | not (validateRules rs nts ts) = error "wrong input format of the rules"
    | otherwise = Grammar nts ts start rs

-- is used for creating transformad grammars
-- creates grammar with no checks (the format of the transformed grammar can be different anyway)
newGrammarNoChecks :: [Symbol] -> [Symbol] -> Symbol -> [Rule] -> Grammar
newGrammarNoChecks nts ts start rs = Grammar nts ts start rs

-- checks the input format of the rules
validateRules :: [Rule] -> [Symbol] -> [Symbol] -> Bool
validateRules [] _ _ = True
validateRules (x:xs) nts ts =
    fst x `elem` nts
    && intersect (snd x) (nts ++ ts) == snd x
    && validateRules xs nts ts

-- generates new grammar with transformed rules so that simple rules are eliminated
removeSimpleRules :: Grammar -> Grammar
removeSimpleRules g = newGrammarNoChecks
    (nterms g)
    (terms g)
    (start g)
    (transformRules (rules g) (getReachableNonTerms (nterms g) (rules g)))

transformRules :: [Rule] -> [NSet] -> [Rule]
transformRules [] _ = []
transformRules (r:rs) sets =
    (if isRuleSimple r
    then []
    else generateNewRules r (map fst (filter (\x -> (fst r) `elem` (snd x)) sets)))
    ++ transformRules rs sets

generateNewRules :: Rule -> [Symbol] -> [Rule]
generateNewRules r [] = []
generateNewRules r (x:xs) = [(x, snd r)] ++ generateNewRules r xs

-- finds for every non-terminal a NSet - set of non-terminals
-- which are reachable by applications of simple rules
getReachableNonTerms :: [Symbol] -> [Rule] -> [NSet]
getReachableNonTerms [] _ = []
getReachableNonTerms (nt:nts) rs = [(nt, findSetN [nt] rs)] ++ getReachableNonTerms nts rs

findSetN :: [Symbol] -> [Rule] -> [Symbol]
findSetN symbs rs =
    if symbs == nextIteration
    then symbs
    else findSetN nextIteration rs
        where nextIteration = findSetNStep symbs rs

findSetNStep :: [Symbol] -> [Rule] -> [Symbol]
findSetNStep symbs [] = symbs
findSetNStep symbs (r:rs) =
    (if
        fst r `elem` symbs &&
        isRuleSimple r &&
        not ((head $ snd r) `elem` symbs)
    then snd r
    else [])
    ++ findSetNStep symbs rs

-- a simple rule is in form A->B where B is a non-terminal
isRuleSimple :: Rule -> Bool
isRuleSimple r = length (snd r) == 1 && all isUpper (head $ snd r)

---------------------------------------------------------

transformToCNF :: Grammar -> Grammar
transformToCNF g = newGrammarNoChecks
    (getNonTerminals  (transformRulesToCNF (rules g)) (nterms g))
    (terms g)
    (start g)
    (transformRulesToCNF (rules g))

getNonTerminals :: [Rule] -> [Symbol] -> [Symbol]
getNonTerminals rs symbs = map head $ group $ sort (map fst rs ++ symbs)

transformRulesToCNF :: [Rule] -> [Rule]
transformRulesToCNF [] = []
transformRulesToCNF (r:rs) = parseRule r ++ transformRulesToCNF rs

-- takes one rule and generates corresponding rules based on the CNF algorithm
parseRule :: Rule -> [Rule]
parseRule r
    -- r is like A -> a, just keep this rule
    | (length $ snd r) == 1 && all isLower (head $ snd r) = [r]
    
    -- r is like A -> BC, just keep this rule
    | (length $ snd r) == 2 && (all isUpper $ concat (snd r)) = [r] 
    
    -- r is like A -> bc, we need to generate (1) A -> b'c' and (2) terminal rules (a' -> a)
    | (length $ snd r) == 2 = [(fst r, map commify (snd r))]
        ++ generateTerminalRule (snd r !! 0)
        ++ generateTerminalRule (snd r !! 1)
        
    -- r is like A -> abcd, we need to generate (1) A -> a'<bcd> and (2) terminal rule (a' -> a)
    -- and (3) rules which decompose the <bcd> non-terminal
    | (length $ snd r) > 2 =
        [(fst r, [commify (head $ snd r)] ++ ["<" ++ (concat $ tail $ snd r) ++ ">"])]
        ++ generateTerminalRule (head $ snd r)
        ++ parseComposedNonTerm (concat $ tail $ snd r) 
        
    -- there should be no other type of rule
    | otherwise = error ("bad rule: " ++ show r)

-- parse the non-terminal in form <abcd> and return list of rules
parseComposedNonTerm :: String -> [Rule]
parseComposedNonTerm rs
    -- if non-terminal len is > 2, we need (1) <ABCD> -> a'<BCD> and (2) terminal rule a' -> a
    -- and (3) further decompose remaining non-terminal <BCD>
    | length rs > 2 = [("<" ++ rs ++ ">", [commify [head rs], "<" ++ tail rs ++ ">"])]
        ++ generateTerminalRule ([head rs])
        ++ parseComposedNonTerm (tail rs)
        
    -- if non-terminal len is 2, (A -> <BC>) we need to generate (1) <BC> -> BC and
    -- (2) terminal rules (b' -> b)
    | length rs == 2 = [("<" ++ rs ++ ">", [commify [head rs] ++ commify (tail rs)])]
        ++ generateTerminalRule ([rs !! 0])
        ++ generateTerminalRule ([rs !! 1])
        
    -- no other rule is possible here
    | otherwise = error ("bad rule: " ++ show rs)

-- generates rule for terminal in form: a' -> a
-- if the input is non-terminal, no rule is needed
generateTerminalRule :: Symbol -> [Rule]
generateTerminalRule s = if all isLower s then [(s ++ "'", [s])] else []

-- adds comma to terminals only, ignores non-terminals
commify :: Symbol -> Symbol
commify s = if all isLower s then s ++ "'" else s

readGrammarFromStr :: [String] -> Grammar
readGrammarFromStr (l1:l2:l3:ls) =
    newGrammar (splitOn "," l1) (splitOn "," l2) l3
        (map (\x -> (head x, map (:[]) $ concat (tail x))) (map (splitOn "->") ls))
readGrammarFromStr _ = error "bad input format"

readAndPrintStr :: String -> String
readAndPrintStr s = show $ readGrammarFromStr $ lines s

removeSimpleRulesStr :: String -> String
removeSimpleRulesStr s = show $ removeSimpleRules $ readGrammarFromStr $ lines s

transformToCNFStr :: String -> String
transformToCNFStr s = show $ transformToCNF $ removeSimpleRules $ readGrammarFromStr $ lines s

dispatch :: [(String, String -> String)]
dispatch =  [("-i", readAndPrintStr), ("-1", removeSimpleRulesStr), ("-2", transformToCNFStr)]

main = do
    args <- getArgs
    if length args < 1 || length args > 2
    then putStrLn "bad arguments"
    else do
        let command = head args

        contents <- (if length args == 2
                     then readFile $ last args
                     else getContents)

        case lookup command dispatch of
            Nothing -> putStrLn "bad arguments"
            Just a -> putStrLn $ a contents