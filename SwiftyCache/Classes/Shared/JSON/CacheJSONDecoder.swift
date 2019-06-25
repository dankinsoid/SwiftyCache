//
//  JSONScanDecoder.swift
//  Coders
//
//  Created by Данил Войдилов on 23/12/2018.
//  Copyright © 2018 daniil. All rights reserved.
//

import Foundation

private let asciiDoubleQuote = UInt8(ascii: "\"")

public final class CacheJSONDecoder {
	
	public var dateDecodingStrategy: DateDecodingStrategy
	public var keyDecodingStrategy: KeyDecodingStrategy
	public var tryDecodeFromQuotedString: Bool
	public var userInfo: [CodingUserInfoKey : Any] = [:]
	
	public init(dateDecodingStrategy: DateDecodingStrategy = .deferredToDate,
				keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys,
				tryDecodeFromQuotedString: Bool = true) {
		self.dateDecodingStrategy = dateDecodingStrategy
		self.keyDecodingStrategy = keyDecodingStrategy
		self.tryDecodeFromQuotedString = tryDecodeFromQuotedString
	}
	
	func decodeValue<D: Decodable>(from data: Data) throws -> D {
		return try decode(D.self, from: data)
	}
	
	public func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D {
		let decoder = try self.decoder(for: data, for: nil)
		if let result = decoder.json as? D { return result }
		return try D.init(from: decoder)
	}
	
	func getObject<D: Decodable>(_ type: D.Type, from data: Data, for storagesContainer: CacheContext) throws -> D {
		let decoder = try self.decoder(for: data, for: storagesContainer)
		if let result = decoder.json as? D { return result }
		return try D.init(from: decoder)
	}
	
	func getAnyObject<D>(_ type: D.Type, from data: Data, for storagesContainer: CacheContext) throws -> D {
		let decoder = try self.decoder(for: data, for: storagesContainer)
		if let result = decoder.json as? D { return result }
		return try ((type as? Decodable.Type)~!.init(from: decoder) as? D)~!
	}
	
	private func decoder(for data: Data, for storagesContainer: CacheContext?) throws -> _Decoder {
		let json = try JSON(from: data)
		return _Decoder(json: json, codingPath: [], userInfo: userInfo, dateDecodingStrategy: dateDecodingStrategy, keyDecodingStrategy: keyDecodingStrategy, tryDecodeFromQuotedString: tryDecodeFromQuotedString, storagesContainer: storagesContainer)
	}
	
}

fileprivate struct _Decoder: Decoder {
	let unboxer: Unboxer
	var userInfo: [CodingUserInfoKey : Any] { return unboxer.userInfo }
	let codingPath: [CodingKey]
	let json: JSON
	
	init(json: JSON, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey : Any] = [:], dateDecodingStrategy: CacheJSONDecoder.DateDecodingStrategy, keyDecodingStrategy: CacheJSONDecoder.KeyDecodingStrategy, tryDecodeFromQuotedString: Bool, storagesContainer: CacheContext?) {
		self.json = json
		self.codingPath = codingPath
		self.unboxer = Unboxer(userInfo: userInfo, dateDecodingStrategy: dateDecodingStrategy, keyDecodingStrategy: keyDecodingStrategy, tryDecodeFromQuotedString: tryDecodeFromQuotedString, storagesContainer: storagesContainer)
	}
	
	init(json: JSON, codingPath: [CodingKey] = [], unboxer: Unboxer) {
		self.json = json
		self.codingPath = codingPath
		self.unboxer = unboxer
	}
	
	func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
		let container = try _KeyedDecodingContainer<Key>(json: json, codingPath: codingPath, unboxer: unboxer)
		return KeyedDecodingContainer(container)
	}
	
	func unkeyedContainer() throws -> UnkeyedDecodingContainer {
		let container = try _UnkeyedDecodingContaier(json: json, codingPath: codingPath, unboxer: unboxer)
		return container
	}
	
	func singleValueContainer() throws -> SingleValueDecodingContainer {
		let container = try _SingleDecodingContainer(json: json, codingPath: codingPath, unboxer: unboxer)
		return container
	}
}

fileprivate struct _KeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
	var codingPath: [CodingKey]
	var allKeys: [Key] { return self.getAllKeys() }
	let json: [String: JSON]
	let unboxer: Unboxer
	
	init(json: JSON, codingPath: [CodingKey], unboxer: Unboxer) throws {
		self.codingPath = codingPath
		self.unboxer = unboxer
		var js: [String: JSON] = [:]
		if case .object(let dict) = json {
			js = dict
		} else if unboxer.tryDecodeFromQuotedString, case .string(let str) = json {
			do {
				let _json = try JSON(from: Data(str.utf8))
				js = try _json.object~!
			} catch {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot get keyed decoding container -- found String value \"\(str)\" instead."))
			}
		} else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot get keyed decoding container -- found \(json.kind.rawValue) value \"\(json.value ?? JSON.null)\" instead."))
		}
		switch unboxer.keyDecodingStrategy {
		case .useDefaultKeys: self.json = js
		case .convertFromSnakeCase:
			var _js: [String: JSON] = [:]
			js.forEach {
				_js[CacheJSONDecoder.KeyDecodingStrategy._convertFromSnakeCase($0.key)] = $0.value
			}
			self.json = _js
		case .custom(let transform):
			var _js: [String: JSON] = [:]
			js.forEach {
				_js[transform(codingPath + [PlainCodingKey($0.key)])] = $0.value
			}
			self.json = _js
		}
	}
	
	func getAllKeys() -> [Key] {
		var result: [Key] = []
		for (keyString, _) in json {
			if let key = Key.init(stringValue: keyString) {
				result.append(key)
			}
		}
		return result
	}
	
	func contains(_ key: Key) -> Bool {
		return json[key.stringValue] != nil
	}
	
	func decodeNil(forKey key: Key) throws -> Bool {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return unboxer.decodeNil(json: js)
	}
	
	func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decode(Bool.self, json: js, codingPath: codingPath + [key])
	}
	
	func decode(_ type: String.Type, forKey key: Key) throws -> String {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decode(String.self, json: js, codingPath: codingPath + [key])
	}
	
	func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decode(Double.self, json: js, codingPath: codingPath + [key])
	}
	
	func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decode(Float.self, json: js, codingPath: codingPath + [key])
	}
	
	@inline(__always)
	func decodeSignedInt<I: SignedBitPatternInitializable>(_ type: I.Type, forKey key: Key) throws -> I {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decodeSignedInt(I.self, json: js, codingPath: codingPath + [key])
	}
	
	func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
		return try decodeSignedInt(type, forKey: key)
	}
	
	func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
		return try decodeSignedInt(type, forKey: key)
	}
	
	func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
		return try decodeSignedInt(type, forKey: key)
	}
	
	func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
		return try decodeSignedInt(type, forKey: key)
	}
	
	func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
		return try decodeSignedInt(type, forKey: key)
	}
	
	@inline(__always)
	func decodeUnsignedInt<I: FixedWidthInteger & UnsignedInteger>(_ type: I.Type, forKey key: Key) throws -> I {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decodeUnsignedInt(I.self, json: js, codingPath: codingPath + [key])
	}
	
	func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
		return try decodeUnsignedInt(type, forKey: key)
	}
	
	func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
		return try decodeUnsignedInt(type, forKey: key)
	}
	
	func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
		return try decodeUnsignedInt(type, forKey: key)
	}
	
	func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
		return try decodeUnsignedInt(type, forKey: key)
	}
	
	func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
		return try decodeUnsignedInt(type, forKey: key)
	}
	
	func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		return try unboxer.decode(T.self, json: js, codingPath: codingPath + [key])
	}
	
	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		var path = codingPath
		path.append(key)
		let container = try _KeyedDecodingContainer<NestedKey>(json: js, codingPath: path, unboxer: unboxer)
		return KeyedDecodingContainer(container)
	}
	
	func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		var path = codingPath
		path.append(key)
		return try _UnkeyedDecodingContaier(json: js, codingPath: path, unboxer: unboxer)
	}
	
	func superDecoder() throws -> Decoder {
		let key = PlainCodingKey("super")
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		var path = codingPath
		path.append(key)
		let decoder = _Decoder(json: js, codingPath: codingPath, unboxer: unboxer)
		return decoder
	}
	
	func superDecoder(forKey key: Key) throws -> Decoder {
		guard let js = json[key.stringValue] else {
			throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key '\(key.stringValue)'."))
		}
		var path = codingPath
		path.append(key)
		return _Decoder(json: js, codingPath: path, unboxer: unboxer)
	}
	
}

fileprivate struct _UnkeyedDecodingContaier: UnkeyedDecodingContainer {
	var codingPath: [CodingKey] = []
	var count: Int? { return json.count }
	var currentIndex: Int = 0
	var isAtEnd: Bool { return currentIndex >= json.count }
	var json: [JSON]
	let unboxer: Unboxer
	
	init(json: JSON, codingPath: [CodingKey], unboxer: Unboxer) throws {
		if case .array(let array) = json {
			self.json = array
		} else if unboxer.tryDecodeFromQuotedString, case .string(let str) = json {
			do {
				let _json = try JSON(from: Data(str.utf8))
				self.json = try _json.array~!
			} catch {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot get unkeyed decoding container -- found String value instead."))
			}
		} else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot get unkeyed decoding container -- found \(json.kind.rawValue) value instead."))
		}
		self.codingPath = codingPath
		self.unboxer = unboxer
	}
	
	mutating func decodeNil() throws -> Bool {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(JSON?.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		if unboxer.decodeNil(json: json[currentIndex]) {
			currentIndex += 1
			return true
		}
		return false
	}
	
	mutating func decode(_ type: Bool.Type) throws -> Bool {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(Bool.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decode(Bool.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	mutating func decode(_ type: String.Type) throws -> String {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(String.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decode(String.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	mutating func decode(_ type: Double.Type) throws -> Double {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(Double.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decode(Double.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	mutating func decode(_ type: Float.Type) throws -> Float {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(Float.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decode(Float.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	@inline(__always)
	mutating func decodeSignedInt<I: SignedBitPatternInitializable>(_ type: I.Type) throws -> I {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(I.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decodeSignedInt(I.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	mutating func decode(_ type: Int.Type) throws -> Int {
		return try decodeSignedInt(type)
	}
	
	mutating func decode(_ type: Int8.Type) throws -> Int8 {
		return try decodeSignedInt(type)
	}
	
	mutating func decode(_ type: Int16.Type) throws -> Int16 {
		return try decodeSignedInt(type)
	}
	
	mutating func decode(_ type: Int32.Type) throws -> Int32 {
		return try decodeSignedInt(type)
	}
	
	mutating func decode(_ type: Int64.Type) throws -> Int64 {
		return try decodeSignedInt(type)
	}
	
	@inline(__always)
	mutating func decodeUnsignedInt<I: FixedWidthInteger & UnsignedInteger>(_ type: I.Type) throws -> I {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(I.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decodeUnsignedInt(I.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	mutating func decode(_ type: UInt.Type) throws -> UInt {
		return try decodeUnsignedInt(type)
	}
	
	mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
		return try decodeUnsignedInt(type)
	}
	
	mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
		return try decodeUnsignedInt(type)
	}
	
	mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
		return try decodeUnsignedInt(type)
	}
	
	mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
		return try decodeUnsignedInt(type)
	}
	
	mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		let result = try unboxer.decode(T.self, json: json[currentIndex], codingPath: codingPath + [PlainCodingKey(currentIndex)])
		currentIndex += 1
		return result
	}
	
	mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound([String: JSON].self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		var path = codingPath
		path.append(PlainCodingKey(currentIndex))
		let container = try _KeyedDecodingContainer<NestedKey>(json: json[currentIndex], codingPath: path, unboxer: unboxer)
		currentIndex += 1
		return KeyedDecodingContainer(container)
	}
	
	mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound([JSON].self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		var path = codingPath
		path.append(PlainCodingKey(currentIndex))
		let container = try _UnkeyedDecodingContaier(json: json[currentIndex], codingPath: path, unboxer: unboxer)
		currentIndex += 1
		return container
	}
	
	mutating func superDecoder() throws -> Decoder {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(JSON.self, DecodingError.Context(codingPath: codingPath + [PlainCodingKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
		}
		var path = codingPath
		path.append(PlainCodingKey(currentIndex))
		let decoder = _Decoder(json: json[currentIndex], codingPath: path, unboxer: unboxer)
		currentIndex += 1
		return decoder
	}
}

fileprivate struct _SingleDecodingContainer: SingleValueDecodingContainer {
	
	let codingPath: [CodingKey]
	let json: JSON
	let unboxer: Unboxer
	
	init(json: JSON, codingPath: [CodingKey], unboxer: Unboxer) throws {
		self.json = json
		self.codingPath = codingPath
		self.unboxer = unboxer
	}
	
	func decodeNil() -> Bool {
		return unboxer.decodeNil(json: json)
	}
	
	func decode(_ type: Bool.Type) throws -> Bool {
		return try unboxer.decode(Bool.self, json: json, codingPath: codingPath)
	}
	
	func decode(_ type: String.Type) throws -> String {
		return try unboxer.decode(String.self, json: json, codingPath: codingPath)
	}
	
	func decode(_ type: Double.Type) throws -> Double {
		return try unboxer.decode(Double.self, json: json, codingPath: codingPath)
	}
	
	func decode(_ type: Float.Type) throws -> Float {
		return try unboxer.decode(Float.self, json: json, codingPath: codingPath)
	}
	
	@inline(__always)
	func decodeSignedInt<I: SignedBitPatternInitializable>(_ type: I.Type) throws -> I {
		return try unboxer.decodeSignedInt(I.self, json: json, codingPath: codingPath)
	}
	
	func decode(_ type: Int.Type) throws -> Int {
		return try decodeSignedInt(type)
	}
	
	func decode(_ type: Int8.Type) throws -> Int8 {
		return try decodeSignedInt(type)
	}
	
	func decode(_ type: Int16.Type) throws -> Int16 {
		return try decodeSignedInt(type)
	}
	
	func decode(_ type: Int32.Type) throws -> Int32 {
		return try decodeSignedInt(type)
	}
	
	func decode(_ type: Int64.Type) throws -> Int64 {
		return try decodeSignedInt(type)
	}
	
	@inline(__always)
	func decodeUnsignedInt<I: FixedWidthInteger & UnsignedInteger>(_ type: I.Type) throws -> I {
		return try unboxer.decodeUnsignedInt(I.self, json: json, codingPath: codingPath)
	}
	
	func decode(_ type: UInt.Type) throws -> UInt {
		return try decodeUnsignedInt(type)
	}
	
	func decode(_ type: UInt8.Type) throws -> UInt8 {
		return try decodeUnsignedInt(type)
	}
	
	func decode(_ type: UInt16.Type) throws -> UInt16 {
		return try decodeUnsignedInt(type)
	}
	
	func decode(_ type: UInt32.Type) throws -> UInt32 {
		return try decodeUnsignedInt(type)
	}
	
	func decode(_ type: UInt64.Type) throws -> UInt64 {
		return try decodeUnsignedInt(type)
	}
	
	func decode<T: Decodable>(_ type: T.Type) throws -> T {
		return try unboxer.decode(T.self, json: json, codingPath: codingPath)
	}
	
}

fileprivate struct Unboxer {
	
	let userInfo: [CodingUserInfoKey : Any]
	let dateDecodingStrategy: CacheJSONDecoder.DateDecodingStrategy
	let keyDecodingStrategy: CacheJSONDecoder.KeyDecodingStrategy
	let tryDecodeFromQuotedString: Bool
	weak var storagesContainer: CacheContext?
	//let cycleIds: Set<String>

	init(userInfo: [CodingUserInfoKey : Any], dateDecodingStrategy: CacheJSONDecoder.DateDecodingStrategy, keyDecodingStrategy: CacheJSONDecoder.KeyDecodingStrategy, tryDecodeFromQuotedString: Bool, storagesContainer: CacheContext?) {
		self.userInfo = userInfo
		self.dateDecodingStrategy = dateDecodingStrategy
		self.keyDecodingStrategy = keyDecodingStrategy
		self.tryDecodeFromQuotedString = tryDecodeFromQuotedString
		self.storagesContainer = storagesContainer
		//self.cycleIds = cycleIds
	}
	
	@inline(__always)
	func decodeNil(json: JSON) -> Bool {
		if case .null = json { return true }
		return false
	}
	
	@inline(__always)
	func decode(_ type: Bool.Type, json: JSON, codingPath: [CodingKey]) throws -> Bool {
		if case .bool(let bool) = json {
			return bool
		}
		if tryDecodeFromQuotedString, case .string(let string) = json {
			if string == "true" { return true }
			if string == "false" { return false }
		}
		throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(json.kind) instead."))
	}
	
	@inline(__always)
	func decode(_ type: String.Type, json: JSON, codingPath: [CodingKey]) throws -> String {
		if case .string(let string) = json {
			return string
		}
		throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(json.kind) instead."))
	}
	
	@inline(__always)
	func decode(_ type: Double.Type, json: JSON, codingPath: [CodingKey]) throws -> Double {
		if case .double(let double) = json {
			return double
		}
		if case .int(let int) = json {
			return Double(int)
		}
		if tryDecodeFromQuotedString, case .string(let string) = json {
			var data = Data(string.utf8)
			data.insert(asciiDoubleQuote, at: 0)
			data.append(asciiDoubleQuote)
			return try data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Double in
				let source = UnsafeBufferPointer(start: bytes, count: data.count)
				var scanner = JSONScanner(source: source, messageDepthLimit: .max)
				do {
					return try scanner.nextDouble()
				} catch  {
					throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: error.localizedDescription, underlyingError: error))
				}
			}
		}
		throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(json.kind) instead."))
	}
	
	@inline(__always)
	func decode(_ type: Float.Type, json: JSON, codingPath: [CodingKey]) throws -> Float {
		return try Float(decode(Double.self, json: json, codingPath: codingPath))
	}
	
	@inline(__always)
	func decodeSignedInt<I: SignedBitPatternInitializable>(_ type: I.Type, json: JSON, codingPath: [CodingKey]) throws -> I {
		if case .int(let int) = json {
			guard int <= I.max && int >= I.min else {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(int)> does not fit in \(type)."))
			}
			return I.init(int)
		}
		if tryDecodeFromQuotedString, case .string(let string) = json {
			var data = Data(string.utf8)
			return try data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> I in
				let source = UnsafeBufferPointer(start: bytes, count: data.count)
				var scanner = JSONScanner(source: source, messageDepthLimit: .max)
				do {
					return try scanner.nextSignedInteger()
				} catch  {
					throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: error.localizedDescription, underlyingError: error))
				}
			}
		}
		throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(json.kind) instead."))
	}
	
	@inline(__always)
	func decodeUnsignedInt<I: FixedWidthInteger & UnsignedInteger>(_ type: I.Type, json: JSON, codingPath: [CodingKey]) throws -> I {
		if case .int(let int) = json {
			guard int <= I.max && int >= I.min else {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(int)> does not fit in \(type)."))
			}
			return I.init(int)
		}
		if tryDecodeFromQuotedString, case .string(let string) = json {
			var data = Data(string.utf8)
			return try data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> I in
				let source = UnsafeBufferPointer(start: bytes, count: data.count)
				var scanner = JSONScanner(source: source, messageDepthLimit: .max)
				do {
					return try scanner.nextUnsignedInteger()
				} catch  {
					throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: error.localizedDescription, underlyingError: error))
				}
			}
		}
		throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(json.kind) instead."))
	}
	
	@inline(__always)
	func decodeDate(from decoder: _Decoder) throws -> Date {
		//_dateFormatter.locale = Locale(identifier: "en_US_POSIX")
		switch dateDecodingStrategy {
		case .deferredToDate: return try Date(from: decoder)
		case .secondsSince1970:
			let seconds = try Double(from: decoder)
			return Date(timeIntervalSince1970: seconds)
		case .millisecondsSince1970:
			let milliseconds = try Double(from: decoder)
			return Date(timeIntervalSince1970: milliseconds / 1000)
		case .iso8601:
			let string = try String(from: decoder)
			return try decodeIso8601(string: string, codingPath: decoder.codingPath)
		case .formatted(let formatter):
			let string = try String(from: decoder)
			if let result = formatter.date(from: string) {
				return result
			} else {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Date string does not match format expected by formatter."))
			}
		case .stringFormats(let formats):
			let string = try String(from: decoder)
			for format in formats {
				_dateFormatter.dateFormat = format
				if let result = _dateFormatter.date(from: string) {
					return result
				}
			}
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Date string does not match any of '\(formats)'."))
		case .custom(let transform):
			return try transform(decoder)
		case .unknown:
			if let seconds = try? Double(from: decoder) {
				return Date(timeIntervalSince1970: seconds)
			}
			if let string = try? String(from: decoder) {
				if let result = try? decodeIso8601(string: string, codingPath: decoder.codingPath) {
					return result
				}
				let dateDetector: NSDataDetector
				do {
					dateDetector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
				} catch {
					throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "NSDataDetector initializer threw an error", underlyingError: error))
				}
				let nsRange = NSRange(location: 0, length: string.count)
				let detectDates = dateDetector.matches(in: string, range: nsRange).compactMap({ $0.date })
				if detectDates.count == 1 {
					return detectDates[0]
				}
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Date format cannot be detected definitely from \"\(string)\"; detected dates: \(detectDates)."))
			}
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Date format cannot be detected."))
		}
	}
	
	@inline(__always)
	func decodeIso8601(string: String, codingPath: [CodingKey]) throws -> Date {
		if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
			if let result = _iso8601Formatter.date(from: string) {
				return result
			} else {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
			}
		} else {
			if let result = _iso8601DateFormatter.date(from: string) {
				return result
			} else {
				throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
			}
		}
	}
	
	@inline(__always)
	func decode<T: Decodable>(_ type: T.Type, json: JSON, codingPath: [CodingKey]) throws -> T {
		if type == JSON.self, let result = json as? T { return result }
		let decoder = _Decoder(json: json, codingPath: codingPath, unboxer: self)
		if type == Date.self || type as? NSDate.Type != nil {
			if let result = try decodeDate(from: decoder) as? T {
				return result
			} else {
				throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(json.kind) instead."))
			}
		}
		if let container = storagesContainer,
			!codingPath.isEmpty,
			type as? CacheReferenceable.Type != nil,
			case .string(let cacheKey) = json {
			let storage = container.anyStorage(of: T.self)
			if let value = storage.object(forKey: cacheKey) {
				return value
			}
		}
		return try T.init(from: decoder)
	}
	
}

let _dateFormatter = DateFormatter()

@available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
let _iso8601Formatter: ISO8601DateFormatter = {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = .withInternetDateTime
	return formatter
}()

let _iso8601DateFormatter: DateFormatter = {
	let formatter = DateFormatter()
	formatter.calendar = Calendar(identifier: .iso8601)
	formatter.locale = Locale(identifier: "en_US_POSIX")
	formatter.timeZone = TimeZone(secondsFromGMT: 0)
	formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
	return formatter
}()
