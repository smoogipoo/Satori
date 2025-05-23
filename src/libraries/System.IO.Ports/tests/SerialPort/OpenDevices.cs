// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using System.Collections.Generic;
using System.Diagnostics;
using System.IO.PortsTests;
using System.Text.RegularExpressions;
using Xunit;

namespace System.IO.Ports.Tests
{
    public class OpenDevices : PortsTest
    {
        [ActiveIssue("Satori: noisy test fails in baseline too")]
        [ConditionalFact(typeof(PlatformDetection), nameof(PlatformDetection.IsNotWindowsNanoServer))] // see https://github.com/dotnet/runtime/issues/26199#issuecomment-390338721
        public void OpenDevices01()
        {
            DosDevices dosDevices = new DosDevices();
            Regex comPortNameRegex = new Regex(@"com\d{1,3}", RegexOptions.IgnoreCase);

            foreach (KeyValuePair<string, string> keyValuePair in dosDevices)
            {
                if (!string.IsNullOrEmpty(keyValuePair.Key) && !comPortNameRegex.IsMatch(keyValuePair.Key))
                {
                    using (SerialPort com1 = new SerialPort(keyValuePair.Key))
                    {
                        Debug.WriteLine($"Checking exception thrown with Key {keyValuePair.Key}");
                        Assert.ThrowsAny<Exception>(() => com1.Open());
                    }
                }

                if (!string.IsNullOrEmpty(keyValuePair.Value) && !comPortNameRegex.IsMatch(keyValuePair.Key))
                {
                    using (SerialPort com1 = new SerialPort(keyValuePair.Value))
                    {
                        Debug.WriteLine($"Checking exception thrown with Value {keyValuePair.Value}");
                        Assert.ThrowsAny<Exception>(() => com1.Open());
                    }
                }
            }
        }
    }
}
