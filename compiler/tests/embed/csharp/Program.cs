// Program.cs - the C# bindings (api/Strata.cs), as Unity / Godot C# would use them.
using System;
static class Program
{
    static void Main()
    {
        Console.WriteLine("version: " + (Strata.Compiler.Version().Length > 0 ? "ok" : "FAILED"));
        Console.WriteLine("check: " + (Strata.Compiler.Check("prog/main.strata") ? "ok" : "FAILED"));
        Strata.Compiler.CheckSource("prog/main.strata", "print(nope)\n");
        string d = Strata.Compiler.Diagnostics();
        Strata.Compiler.Reset();
        Console.Write(d.Replace("\r", ""));
        Console.WriteLine("build: " + (Strata.Compiler.Build("prog/main.strata") ? "ok" : "FAILED"));
    }
}
