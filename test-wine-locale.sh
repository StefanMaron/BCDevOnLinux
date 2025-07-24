#!/bin/bash

echo "Testing Wine locale functions in container..."

docker run --rm --entrypoint /bin/bash bcdevonlinux-bc -c '
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Start Xvfb
Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
sleep 2

# Create a simple C# test program
cat > /tmp/TestLocale.cs << "EOF"
using System;
using System.Globalization;
using System.Runtime.InteropServices;

class TestLocale
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern int LocaleNameToLCID(string lpName, uint dwFlags);
    
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool IsValidLocaleName(string lpLocaleName);
    
    static void Main()
    {
        Console.WriteLine("=== Testing Wine Locale Functions ===\n");
        
        // Test 1: Direct Windows API
        Console.WriteLine("Test 1: LocaleNameToLCID via P/Invoke");
        int lcid = LocaleNameToLCID("en-US", 0);
        Console.WriteLine($"LocaleNameToLCID(\"en-US\") = 0x{lcid:X4} (Error: {Marshal.GetLastWin32Error()})");
        
        // Test 2: IsValidLocaleName
        Console.WriteLine("\nTest 2: IsValidLocaleName via P/Invoke");
        bool valid = IsValidLocaleName("en-US");
        Console.WriteLine($"IsValidLocaleName(\"en-US\") = {valid} (Error: {Marshal.GetLastWin32Error()})");
        
        // Test 3: .NET CultureInfo
        Console.WriteLine("\nTest 3: CultureInfo.GetCultureInfo");
        try
        {
            var culture = CultureInfo.GetCultureInfo("en-US");
            Console.WriteLine($"SUCCESS: CultureInfo.GetCultureInfo(\"en-US\") = {culture.Name} (LCID: {culture.LCID})");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"FAILED: {ex.GetType().Name}: {ex.Message}");
            Console.WriteLine($"Stack trace:\n{ex.StackTrace}");
        }
        
        // Test 4: List all cultures
        Console.WriteLine("\nTest 4: Enumerating cultures");
        try
        {
            var cultures = CultureInfo.GetCultures(CultureTypes.AllCultures);
            Console.WriteLine($"Total cultures: {cultures.Length}");
            int count = 0;
            foreach (var c in cultures)
            {
                if (c.Name.StartsWith("en"))
                {
                    Console.WriteLine($"  - {c.Name} (LCID: {c.LCID})");
                    count++;
                }
            }
            Console.WriteLine($"Found {count} English cultures");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"FAILED to enumerate: {ex.Message}");
        }
    }
}
EOF

# Compile and run
cd /tmp
dotnet new console -n TestLocale -o /tmp/TestLocale >/dev/null 2>&1
cp TestLocale.cs /tmp/TestLocale/Program.cs
cd /tmp/TestLocale
dotnet build >/dev/null 2>&1
echo ""
wine dotnet TestLocale.dll
'