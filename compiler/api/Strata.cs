// Strata.cs - C# bindings for libstrata (the Strata compiler as a library).
// Copyright © 2026 Connor Rutberg. GPL-3.0 with the Strata Embedding Exception
// (LICENSE-EMBEDDING.md): any program may use it, whatever its own license.
//
// Put libstrata.dll (and the lib/ folder beside it) next to your executable, or on PATH.
// Works with .NET, Unity, Godot C#, Stride, Flax - anything that can P/Invoke.
//
//     if (!Strata.Compiler.Check("game/main.strata"))
//         Console.Error.Write(Strata.Compiler.Diagnostics());
//
// Returned strings are copied into .NET strings, so they stay valid after Reset().

using System;
using System.Runtime.InteropServices;

namespace Strata
{
    public static class Compiler
    {
        const string Lib = "libstrata";

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr strata_version();
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        static extern bool strata_check(byte[] path);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        static extern bool strata_check_source(byte[] path, byte[] source);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        static extern bool strata_build(byte[] target, [MarshalAs(UnmanagedType.I1)] bool release, [MarshalAs(UnmanagedType.I1)] bool force);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr strata_output_path(byte[] target);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr strata_diagnostics();
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void strata_set_libdir(byte[] dir);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void strata_reset();

        // UTF-8 + NUL in, UTF-8 out
        static byte[] Utf8(string s) => System.Text.Encoding.UTF8.GetBytes((s ?? "") + "\0");
        static string Str(IntPtr p)
        {
            if (p == IntPtr.Zero) return "";
            int n = 0;
            while (Marshal.ReadByte(p, n) != 0) n++;
            byte[] b = new byte[n];
            Marshal.Copy(p, b, 0, n);
            return System.Text.Encoding.UTF8.GetString(b);
        }

        public static string Version() => Str(strata_version());
        public static string Diagnostics() => Str(strata_diagnostics());

        public static bool Check(string path) => strata_check(Utf8(path));
        public static bool CheckSource(string path, string source) => strata_check_source(Utf8(path), Utf8(source));

        public static bool Build(string target, bool release = false, bool force = false) => strata_build(Utf8(target), release, force);
        public static string OutputPath(string target) => Str(strata_output_path(Utf8(target)));

        public static void SetLibDir(string dir) => strata_set_libdir(Utf8(dir));
        public static void Reset() => strata_reset();
    }
}
