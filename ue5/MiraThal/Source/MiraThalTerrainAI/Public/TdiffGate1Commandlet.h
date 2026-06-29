// TdiffGate1Commandlet.h - the "Gate 1" proof-of-correctness commandlet.
//
// PLAIN ENGLISH:
// A "commandlet" is a little headless program you run through the Unreal editor executable
// from the command line - no game window, no level. Gate 1's job is to PROVE the NNE GPU
// inference path produces the right answers before we build anything on top of it.
//
// It does this by replaying a "golden" recording: the original Python/PyTorch pipeline was
// run once with a fixed seed (12345) and we saved every network's exact inputs AND its exact
// output to disk as raw float32 files. This commandlet feeds those same inputs through our
// Unreal NNE runner and checks the output matches the saved golden output within a small
// tolerance (DirectML's fp math differs slightly from PyTorch's, so we don't demand bit-exact).
//
// Invoked as:  UnrealEditor-Cmd.exe MiraThal.uproject -run=TdiffGate1 [switches]
// (UE strips the "Commandlet" suffix, so UTdiffGate1Commandlet -> "-run=TdiffGate1".)
// See GATE1_HOWTO.md for the full command line.
#pragma once

#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "TdiffGate1Commandlet.generated.h"

UCLASS()
class UTdiffGate1Commandlet : public UCommandlet
{
	GENERATED_BODY()

public:
	UTdiffGate1Commandlet();

	/** Entry point. Params is the raw command-line tail (everything after -run=TdiffGate1). */
	virtual int32 Main(const FString& Params) override;
};
