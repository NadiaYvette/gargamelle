package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func findSeed(name string) string {
	candidates := []string{
		filepath.Join("seeds", name),
		filepath.Join(os.Getenv("HOME"), "src/plans/seeds", name),
		filepath.Join("..", "seeds", name),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return filepath.Join("seeds", name)
}

func main() {
	fmt.Println("=== [TP-SMIRK-007A Task Runner (Go)] ===")

	// 1. Copy Smirk.hs
	srcSeed := findSeed("TP-SMIRK-007A-LiquidSmirk.hs")
	dstSeed := "packages/gargamelle-core/src/Gargamelle/Core/Institution/Liquid/Smirk.hs"
	if err := copyFile(srcSeed, dstSeed); err != nil {
		fmt.Fprintf(os.Stderr, "failed to copy %s -> %s: %v\n", srcSeed, dstSeed, err)
		os.Exit(1)
	}
	fmt.Printf("  [+] Mounted %s\n", dstSeed)

	// 2. Update packages/gargamelle-core/gargamelle-core.cabal
	cabalPath := "packages/gargamelle-core/gargamelle-core.cabal"
	cabalBytes, err := os.ReadFile(cabalPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s: %v\n", cabalPath, err)
		os.Exit(1)
	}
	cabalStr := string(cabalBytes)
	if !strings.Contains(cabalStr, "Gargamelle.Core.Institution.Liquid.Smirk") {
		cabalStr = strings.Replace(cabalStr,
			"    Gargamelle.Core.Institution.Liquid.Polytropos\n",
			"    Gargamelle.Core.Institution.Liquid.Polytropos\n    Gargamelle.Core.Institution.Liquid.Smirk\n", 1)
		if err := os.WriteFile(cabalPath, []byte(cabalStr), 0644); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write %s: %v\n", cabalPath, err)
			os.Exit(1)
		}
		fmt.Println("  [+] Updated gargamelle-core.cabal")
	}

	// 3. Update packages/gargamelle-core/test/Main.hs
	testPath := "packages/gargamelle-core/test/Main.hs"
	testBytes, err := os.ReadFile(testPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s: %v\n", testPath, err)
		os.Exit(1)
	}
	testStr := string(testBytes)
	if !strings.Contains(testStr, "Gargamelle.Core.Institution.Liquid.Smirk") {
		testStr = strings.Replace(testStr,
			"import Gargamelle.Core.Institution.Liquid.Penelope\n",
			"import Gargamelle.Core.Institution.Liquid.Penelope\nimport Gargamelle.Core.Institution.Liquid.Smirk\n", 1)
	}
	if !strings.Contains(testStr, "Smirk and dunning-t-digest Liquid Measures") {
		testSnippet := `
  describe "Smirk and dunning-t-digest Liquid Measures (TP-SMIRK-007A)" $ do
    let emptySig = LiquidSig mempty mempty [] mempty mempty []
        smirkSig = registerAllSmirkMeasures emptySig

    it "registers Fuel conservation measures and budget qualifiers" $ do
      Map.member "stepsConsumed" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "fuelRemaining" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "grantedFuel" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "effectiveFuel" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Set.member "Fuel" (sigSorts smirkSig) ` + "`shouldBe`" + ` True
      Set.size (fuelBudgetQualifiers) ` + "`shouldBe`" + ` 5

    it "registers Evacuable non-empty matching and termination qualifiers" $ do
      Map.member "isNullableAST" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "matchLength" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "remainingInputLen" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Set.member "AST" (sigSorts smirkSig) ` + "`shouldBe`" + ` True
      Set.size (evacuableQualifiers) ` + "`shouldBe`" + ` 2

    it "registers dunning-t-digest capacity and monotonic qualifiers" $ do
      Map.member "centroidCount" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "maxCentroids" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "centroidMean" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Map.member "centroidWeight" (sigMeasures smirkSig) ` + "`shouldBe`" + ` True
      Set.member "TDigest" (sigSorts smirkSig) ` + "`shouldBe`" + ` True
      Set.size (tDigestQualifiers) ` + "`shouldBe`" + ` 3
`
		testStr = strings.Replace(testStr,
			"main :: IO ()\nmain = hspec $ do\n",
			"main :: IO ()\nmain = hspec $ do\n"+testSnippet, 1)
	}
	if err := os.WriteFile(testPath, []byte(testStr), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "failed to write %s: %v\n", testPath, err)
		os.Exit(1)
	}
	fmt.Println("  [+] Updated test/Main.hs")

	fmt.Println("=== [TP-SMIRK-007A Task Runner Complete] ===")
}
