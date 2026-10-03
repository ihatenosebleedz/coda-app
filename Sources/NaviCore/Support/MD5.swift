import Foundation

public enum MD5 {

    private static let s: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    private static let k: [UInt32] = (0..<64).map { i in
        UInt32(truncatingIfNeeded: Int64(abs(sin(Double(i + 1))) * 4_294_967_296.0))
    }

    public static func hex(_ input: String) -> String {
        hex(Array(input.utf8))
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        var message = bytes
        let bitLength = UInt64(bytes.count) &* 8

        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 0, to: 64, by: 8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var m = [UInt32](repeating: 0, count: 16)
            for j in 0..<16 {
                let base = chunkStart + j * 4
                m[j] = UInt32(message[base])
                    | (UInt32(message[base + 1]) << 8)
                    | (UInt32(message[base + 2]) << 16)
                    | (UInt32(message[base + 3]) << 24)
            }

            var a = a0, b = b0, c = c0, d = d0

            for i in 0..<64 {
                var f: UInt32
                var g: Int
                switch i {
                case 0..<16:
                    f = (b & c) | (~b & d)
                    g = i
                case 16..<32:
                    f = (d & b) | (~d & c)
                    g = (5 &* i &+ 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 &* i &+ 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 &* i) % 16
                }

                f = f &+ a &+ k[i] &+ m[g]
                a = d
                d = c
                c = b
                b = b &+ rotateLeft(f, by: s[i])
            }

            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        return [a0, b0, c0, d0]
            .map { word in
                (0..<4)
                    .map { byte in
                        let value = UInt8(truncatingIfNeeded: word >> UInt32(byte * 8))
                        return String(format: "%02x", value)
                    }
                    .joined()
            }
            .joined()
    }

    private static func rotateLeft(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value << amount) | (value >> (32 - amount))
    }
}
