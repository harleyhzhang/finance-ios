// Local macOS helper: secret material crosses stdin/stdout pipes, never process arguments.
import Foundation
import Security
let args = CommandLine.arguments
func fail() -> Never { fputs("Finance Keychain operation failed.\n",stderr); exit(1) }
// Usage: finance-keychain read|create SERVICE
guard args.count == 3 else { fail() }
let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:args[2],kSecAttrAccount as String:"production-v1"]
if args[1] == "read" {
    var q = query; q[kSecReturnData as String] = true
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { fail() }
    FileHandle.standardOutput.write(data)
} else if args[1] == "create" {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count > 0, data.count < 4096 else { fail() }
    var q = query; q[kSecValueData as String] = data
    q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { fail() }
} else { fail() }
