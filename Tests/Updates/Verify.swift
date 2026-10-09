import Foundation
import CryptoKit

// Verify release artifacts independently, using only the embedded public key.
let args = CommandLine.arguments
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
guard args.count == 4 else { fail("Usage: verify-update app archive appcast") }
let app = URL(fileURLWithPath: args[1])
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
guard let encodedKey = info["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: encodedKey) else { fail("No embedded update key") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let feedBytes = try Data(contentsOf: URL(fileURLWithPath: args[3]))
let feed = try XMLDocument(data: feedBytes)
guard let text = String(data: feedBytes, encoding: .utf8),
      let marker = text.range(of: "<!-- sparkle-signatures:", options: .backwards) else { fail("Unsigned feed") }
let signedBody = Data(text[..<marker.lowerBound].utf8)
let footer = String(text[marker.lowerBound...])
let expression = try NSRegularExpression(pattern: #"edSignature: ([A-Za-z0-9+/=]+)\s+length: ([0-9]+)"#)
guard let match = expression.firstMatch(in: footer, range: NSRange(footer.startIndex..., in: footer)),
      let signatureRange = Range(match.range(at: 1), in: footer),
      let lengthRange = Range(match.range(at: 2), in: footer),
      let feedSignature = Data(base64Encoded: String(footer[signatureRange])),
      Int(footer[lengthRange]) == signedBody.count,
      key.isValidSignature(feedSignature, for: signedBody) else { fail("Invalid feed signature") }
var badFeed = signedBody
badFeed.append(32)
guard !key.isValidSignature(feedSignature, for: badFeed) else { fail("Tampered feed accepted") }
guard let item = try feed.nodes(forXPath: "/rss/channel/item").first as? XMLElement,
      let enclosure = item.elements(forName: "enclosure").first,
      let signatureText = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
      let signature = Data(base64Encoded: signatureText),
      let expectedLength = enclosure.attribute(forName: "length")?.stringValue.flatMap(Int.init) else { fail("Invalid appcast") }
let bytes = try Data(contentsOf: URL(fileURLWithPath: args[2]))
guard bytes.count == expectedLength, key.isValidSignature(signature, for: bytes) else { fail("Archive signature/length verification failed") }
guard item.elements(forName: "sparkle:version").first?.stringValue == info["CFBundleVersion"] as? String else { fail("Build mismatch") }
var tampered = bytes
if !tampered.isEmpty { tampered[0] ^= 1 }
guard !key.isValidSignature(signature, for: tampered) else { fail("Tampering was accepted") }
let otherKey = Curve25519.Signing.PrivateKey().publicKey
guard !otherKey.isValidSignature(signature, for: bytes) else { fail("Wrong signing key was accepted") }
print("PASS signed feed, archive signature, byte count and build; tampered bytes and wrong key rejected")
