using System;
using System.Security.Cryptography;

namespace BCPasswordHasher
{
    /// <summary>
    /// BC Password Hasher - Uses exact Business Central password hashing algorithm
    ///
    /// Implements the algorithm from:
    ///   BCDecompiled/Microsoft.Dynamics.Nav.Core/CryptographyHelper.cs
    ///   BCDecompiled/Microsoft.Dynamics.Nav.Core/RsaEncryptionProviderBase.cs
    ///
    /// Usage: BCPasswordHasher <password> <user_guid>
    /// Example: BCPasswordHasher "P@ssw0rd123" "12345678-1234-1234-1234-123456789abc"
    /// </summary>
    class Program
    {
        // Constants from RsaEncryptionProviderBase
        private const int Iterations = 100000;

        static int Main(string[] args)
        {
            if (args.Length != 2)
            {
                Console.Error.WriteLine("Usage: BCPasswordHasher <password> <user_guid>");
                Console.Error.WriteLine();
                Console.Error.WriteLine("Example:");
                Console.Error.WriteLine("  BCPasswordHasher \"P@ssw0rd123\" \"12345678-1234-1234-1234-123456789abc\"");
                return 1;
            }

            string password = args[0];
            string userGuidStr = args[1];

            // Validate GUID
            if (!Guid.TryParse(userGuidStr, out Guid userGuid))
            {
                Console.Error.WriteLine($"Error: Invalid GUID format: {userGuidStr}");
                return 1;
            }

            try
            {
                // Generate hash using BC's exact algorithm
                string passwordHash = GenerateSaltedPasswordHashFromPassword(password, userGuid);
                Console.WriteLine(passwordHash);
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Error generating password hash: {ex.Message}");
                return 1;
            }
        }

        /// <summary>
        /// Generate base password hash with empty GUID salt
        /// From CryptographyHelper.cs line 27-30
        /// </summary>
        public static string GeneratePasswordHash(string password)
        {
            return GenerateSaltedPasswordHash(password, Guid.Empty);
        }

        /// <summary>
        /// Generate salted password hash
        /// Exact code from CryptographyHelper.cs line 21-25
        /// </summary>
        public static string GenerateSaltedPasswordHash(string passwordHash, Guid salt)
        {
            byte[] byteArray = salt.ToByteArray();
            return string.Join("-",
                Convert.ToBase64String(
                    new Rfc2898DeriveBytes(
                        passwordHash,
                        byteArray,
                        salt.Equals(Guid.Empty) ? 1 : Iterations,
                        HashAlgorithmName.SHA256
                    ).GetBytes(byteArray.Length)
                ),
                "V3"
            );
        }

        /// <summary>
        /// Generate salted password hash from plain password
        /// Exact code from CryptographyHelper.cs line 32-35
        /// </summary>
        public static string GenerateSaltedPasswordHashFromPassword(string password, Guid salt)
        {
            return GenerateSaltedPasswordHash(GeneratePasswordHash(password), salt);
        }
    }
}
