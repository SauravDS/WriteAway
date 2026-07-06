import Foundation

func assertEqual<T: Equatable>(_ a: T, _ b: T, line: UInt = #line) {
    if a != b {
        print("❌ Test failed on line \(line): expected \(b), got \(a)")
        exit(1)
    }
}

func testSanitize() {
    let mounter = Mounter()
    
    // Basic safe names
    assertEqual(mounter.sanitize("My Drive"), "My Drive")
    assertEqual(mounter.sanitize("Windows_10"), "Windows_10")
    assertEqual(mounter.sanitize("BACKUP-1"), "BACKUP-1")
    
    // Names with unsafe characters
    assertEqual(mounter.sanitize("My'Drive"), "MyDrive")
    assertEqual(mounter.sanitize("Test\"Drive"), "TestDrive")
    assertEqual(mounter.sanitize("Bad`Name"), "BadName")
    assertEqual(mounter.sanitize("Data$!@#"), "Data")
    
    // Empty string fallback
    assertEqual(mounter.sanitize("!@#$"), "NTFS Volume")
}

func testShellEscape() {
    assertEqual(Shell.shellEscape("hello"), "'hello'")
    assertEqual(Shell.shellEscape("hello'world"), "'hello'\\''world'")
    assertEqual(Shell.shellEscape("hello\"world"), "'hello\"world'")
    assertEqual(Shell.shellEscape("hello\\world"), "'hello\\world'")
}

@main
struct RunTests {
    static func main() {
        print("Running tests...")
        testSanitize()
        testShellEscape()
        print("✅ All tests passed!")
    }
}
