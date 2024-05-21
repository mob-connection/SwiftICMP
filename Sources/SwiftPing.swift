//  MIT License
//
//  Copyright (c) 2024 mob-connection (Oleksandr Zhurba)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Darwin
import Foundation

public enum ICMPError: Error {
	case converCString
	case packatLenght
	case headerVersion
	case `protocol`
	case packetCount
	case noSigPipe(String)
	case rcvTimeOut(String)
	case sendTo(String)
	case recvFrom(String)
	case checksum
	case checksumOut
	case type
	case code
	case identifier
	case sequence
	case payload

}

public struct IPHeader {
	public let versionAndHeaderLength: UInt8
	public let differentiatedServices: UInt8
	public let totalLength: UInt16
	public let identification: UInt16
	public let flagsAndFragmentOffset: UInt16
	public let timeToLive: UInt8
	public let `protocol`: UInt8
	public let headerChecksum: UInt16
	public let sourceAddress: (UInt8, UInt8, UInt8, UInt8)
	public let destinationAddress: (UInt8, UInt8, UInt8, UInt8)

}

public enum ICMPType: UInt8 {
	case v4EchoReplay = 0
	case v4EchoRequest = 8

}

public struct ICMPHeader {
	public var type: UInt8
	public var code: UInt8
	public var checksum: UInt16
	public var identifier: UInt16
	public var sequenceNumber: UInt16
	public var payload: uuid_t

}

public struct Response {
	public let ipHeader: IPHeader
	public let icmpHeader: ICMPHeader
	public let time: TimeInterval

}

public actor ICMPBuilder {
	public static func createPackageV4(
		sequence: UInt16
	) throws -> ICMPHeader {
		var header = ICMPHeader(
			type: ICMPType.v4EchoRequest.rawValue,
			code: 0,
			checksum: 0,
			identifier: CFSwapInt16HostToBig(UInt16.random(in: 0..<UInt16.max)),
			sequenceNumber: CFSwapInt16HostToBig(sequence),
			payload: UUID().uuid
		)
		header.checksum = try ICMPBuilder.checksum(packet: header)
		return header
	}

	public static func checksum(
		packet: ICMPHeader
	) throws -> UInt16 {
		var packet = packet
		packet.checksum = 0
		var checksum: UInt64 = 0
		let packetBuffer = withUnsafeBytes(of: &packet) { Data($0) }
		for i in stride(from: 0, to: packetBuffer.count, by: 2) {
			var word: UInt64
			if i + 1 < packetBuffer.count {
				word = UInt64(packetBuffer[i]) << 8 | UInt64(packetBuffer[i + 1])
			} else {
				word = UInt64(packetBuffer[i]) << 8
			}
			checksum += word
		}
		checksum = (checksum >> 16) + (checksum & 0xffff)
		checksum = checksum + (checksum >> 16)

		guard checksum < UInt16.max else { throw ICMPError.checksumOut }
		return ~CFSwapInt16HostToBig(UInt16(checksum))
	}

	public static func headerOffsetIPv4(
		packet: Data
	) throws -> Int {
		guard packet.count >= MemoryLayout<IPHeader>.size + MemoryLayout<ICMPHeader>.size else { throw ICMPError.packatLenght }
		let ipHeader = packet.withUnsafeBytes { $0.load(as: IPHeader.self) }
		guard ipHeader.versionAndHeaderLength & 0xF0 == 0x40 else { throw ICMPError.headerVersion } // IPv4
		guard ipHeader.protocol == IPPROTO_ICMP else { throw ICMPError.protocol } // ICMP
		let headerLength = Int(ipHeader.versionAndHeaderLength) & 0x0F * MemoryLayout<UInt32>.size
		guard packet.count >= headerLength + MemoryLayout<IPHeader>.size else { throw ICMPError.packetCount }
		return headerLength
	}

	public static func toPointer(
		packet: inout ICMPHeader
	) -> UnsafeMutableRawPointer {
		withUnsafeMutablePointer(to: &packet) { UnsafeMutableRawPointer($0) }
	}

}

public actor ICMPSender {
	public typealias Byte = UInt8
	public typealias Bytes = [Byte]
	public let kMaxPackageSize = 128
	private var remoteAddrIn = sockaddr_in()
	private var socketAddress = sockaddr_storage()
	private let remoteAddrPointer: UnsafePointer<sockaddr>
	private let socketAddressPointer: UnsafeMutablePointer<sockaddr>
	private var socketStorageLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
	private let socketFD: Int32
	private let host: String
	private let timeout: timeval

	public init(
		host: String,
		timeval: timeval = timeval(tv_sec: 1, tv_usec: 0)
	) async throws {
		self.host = host
		self.timeout = timeval

		guard let remoteHost = host.cString(using: .utf8) else {
			throw ICMPError.converCString
		}
		remoteAddrIn.sin_family = sa_family_t(AF_INET)
		remoteAddrIn.sin_addr.s_addr = inet_addr(remoteHost)
		remoteAddrIn.sin_port = 0

		// create pointers
		remoteAddrPointer = withUnsafePointer(to: &remoteAddrIn) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }
		socketAddressPointer = withUnsafeMutablePointer(to: &socketAddress) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }

		// create socket
		socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)

		// set socket option NOSIGPIPE
		var NOSIGPIPE = 1
		try checker(
			status: { Int(setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &NOSIGPIPE, socklen_t(MemoryLayout.size(ofValue: NOSIGPIPE)))) },
			interface: .noSigPipe("noSigPipe")
		)

		// set socket option SO_RCVTIMEO
		var RCVTIMEO = timeval
		try checker(
			status: { Int(setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &RCVTIMEO, socklen_t(MemoryLayout.size(ofValue: RCVTIMEO)))) },
			interface: .rcvTimeOut("rcvTimeOut")
		)
	}

	public func send(
		sequence: UInt16
	) throws -> Response {
		let start = Date().timeIntervalSince1970

		var response = Bytes(repeating: 0, count: kMaxPackageSize)

		// create ICMPHeader header
		var header = try ICMPBuilder.createPackageV4(sequence: sequence)

		// create header pointer
		let headerPointer = ICMPBuilder.toPointer(packet: &header)

		// send package
		try checker(
			status: { sendto(socketFD, headerPointer, MemoryLayout<ICMPHeader>.size, 0, remoteAddrPointer, socklen_t(MemoryLayout.size(ofValue: remoteAddrPointer))) },
			interface: .sendTo("sendto")
		)

		// receive response
		try checker(
			status: { recvfrom(socketFD, &response, kMaxPackageSize, 0, socketAddressPointer, &socketStorageLength) },
			interface: .recvFrom("recvFrom")
		)

		sleep(UInt32(timeout.tv_sec))
		usleep(UInt32(timeout.tv_usec))

		// validate response
		return try validate(response: response, headerSent: header, startTime: start)
	}

	private func validate(
		response: Bytes,
		headerSent: ICMPHeader,
		startTime: TimeInterval
	) throws -> Response {
		let data = Data(response)
		let ipHeader = data.withUnsafeBytes { $0.load(as: IPHeader.self) }
		let headerOffset = try ICMPBuilder.headerOffsetIPv4(packet: data)
		let dataRange = data.subdata(in: headerOffset..<data.count)
		let icmpHeader = dataRange.withUnsafeBytes { $0.load(as: ICMPHeader.self) }
		let checksum = try ICMPBuilder.checksum(packet: icmpHeader)
		guard icmpHeader.type == ICMPType.v4EchoReplay.rawValue else { throw ICMPError.type }
		guard icmpHeader.code == 0 else { throw ICMPError.code }
		guard checksum == icmpHeader.checksum else { throw ICMPError.checksum }
		guard icmpHeader.identifier == headerSent.identifier else { throw ICMPError.identifier }
		guard icmpHeader.sequenceNumber == headerSent.sequenceNumber else { throw ICMPError.sequence }
		guard icmpHeader.payload == headerSent.payload else { throw ICMPError.payload }
		let endTime = Date().timeIntervalSince1970
		let delta = endTime - startTime - Double(timeout.tv_sec) - Double(timeout.tv_usec / 1_000_000)
		return Response(ipHeader: ipHeader, icmpHeader: icmpHeader, time: delta)
	}

	deinit {
		close(socketFD)
	}

	private func checker(
		status: () -> (Int),
		interface: ICMPError
	) throws {
		guard status() < 0 else { return }

		let erroDesc = String(cString: strerror(errno))

		if case .noSigPipe = interface {
			throw ICMPError.noSigPipe(erroDesc)
		} else if case .rcvTimeOut = interface {
			throw ICMPError.rcvTimeOut(erroDesc)
		} else if case .sendTo = interface {
			throw ICMPError.sendTo(erroDesc)
		} else if case .recvFrom = interface {
			throw ICMPError.recvFrom(erroDesc)
		}
	}

}

public func == (
	lhs: uuid_t,
	rhs: uuid_t
) -> Bool {
	lhs.0 == rhs.0 &&
	lhs.1 == rhs.1 &&
	lhs.2 == rhs.2 &&
	lhs.3 == rhs.3 &&
	lhs.4 == rhs.4 &&
	lhs.5 == rhs.5 &&
	lhs.6 == rhs.6 &&
	lhs.7 == rhs.7 &&
	lhs.8 == rhs.8 &&
	lhs.9 == rhs.9 &&
	lhs.10 == rhs.10 &&
	lhs.11 == rhs.11 &&
	lhs.12 == rhs.12 &&
	lhs.13 == rhs.13 &&
	lhs.14 == rhs.14 &&
	lhs.15 == rhs.15

}
