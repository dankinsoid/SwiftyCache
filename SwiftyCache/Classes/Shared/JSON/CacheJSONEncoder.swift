//
//  MyJSONEncoder.swift
//  Coders
//
//  Created by Данил Войдилов on 24/12/2018.
//  Copyright © 2018 daniil. All rights reserved.
//

import Foundation

struct ReferenceObjectInfo {
	var references: [String: Set<String>] = [:]
}

public final class CacheJSONEncoder {
	
	var dateEncodingStrategy: DateEncodingStrategy
	var keyEncodingStrategy: KeyEncodingStrategy
	var userInfo: [CodingUserInfoKey : Any] = [:]
	
	public init(dateEncodingStrategy: DateEncodingStrategy = .deferredFromDate,
		 keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys) {
		self.dateEncodingStrategy = dateEncodingStrategy
		self.keyEncodingStrategy = keyEncodingStrategy
	}
	
	public func encode<T: Encodable>(_ value: T) throws -> Data {
		if let data = (value as? JSON)?.data { return data }
		let encoder = self.encoder(cacheInfo: nil)
		try value.encode(to: encoder)
		return encoder.storage.data
	}
	
	func encodeAny<T>(_ value: T) throws -> Data {
		if let data = (value as? JSON)?.data { return data }
		let encoder = self.encoder(cacheInfo: nil)
		try (value as? Encodable)~!.encode(to: encoder)
		return encoder.storage.data
	}
	
	func save<T: Encodable>(_ value: T, to storagesContainer: CacheContext, key: String, storage: String) throws -> (Data, referencing: [String: Set<String>]) {
		if let data = (value as? JSON)?.data { return (data, [:]) }
		let referenceKeys = DictClass<Set<String>>()
		let cahceInfo = BoxerCacheInfo(storagesContainer: storagesContainer, rootKey: key, rootStorageName: storage, referenceKeys: referenceKeys)
		let encoder = self.encoder(cacheInfo: cahceInfo)
		try value.encode(to: encoder)
		return (encoder.storage.data, referenceKeys.dict)
	}
	
	func saveAny<T>(_ value: T, to storagesContainer: CacheContext, key: String, storage: String) throws -> (Data, referencing: [String: Set<String>]) {
		if let data = (value as? JSON)?.data { return (data, [:]) }
		let referenceKeys = DictClass<Set<String>>()
		let cahceInfo = BoxerCacheInfo(storagesContainer: storagesContainer, rootKey: key, rootStorageName: storage, referenceKeys: referenceKeys)
		let encoder = self.encoder(cacheInfo: cahceInfo)
		try (value as? Encodable)~!.encode(to: encoder)
		return (encoder.storage.data, referenceKeys.dict)
	}
	
	func goThrough<T>(_ value: T, to storagesContainer: CacheContext, key: String, storage: String) throws -> [String: Set<String>] {
		let referenceKeys = DictClass<Set<String>>()
		let cahceInfo = BoxerCacheInfo(storagesContainer: storagesContainer, rootKey: key, rootStorageName: storage, referenceKeys: referenceKeys)
		let encoder = self.encoder(cacheInfo: cahceInfo)
		try (value as? Encodable)~!.encode(to: encoder)
		return referenceKeys.dict
	}
	
	private func encoder(cacheInfo: BoxerCacheInfo?) -> _Encoder {
		return _Encoder(dateEncodingStrategy: dateEncodingStrategy, keyEncodingStrategy: keyEncodingStrategy, cacheInfo: cacheInfo)
	}
	
}

fileprivate struct _Encoder: Encoder {
	let storage: RefJson
	let boxer: Boxer
	var userInfo: [CodingUserInfoKey : Any] { return boxer.userInfo }
	let codingPath: [CodingKey]
	
	init(storage: RefJson = .null, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey : Any] = [:], dateEncodingStrategy: CacheJSONEncoder.DateEncodingStrategy, keyEncodingStrategy: CacheJSONEncoder.KeyEncodingStrategy, cacheInfo: BoxerCacheInfo?) {
		//self.json = json
		self.storage = storage
		self.codingPath = codingPath
		self.boxer = Boxer(userInfo: userInfo, dateEncodingStrategy: dateEncodingStrategy, keyEncodingStrategy: keyEncodingStrategy, cacheInfo: cacheInfo)
	}
	
	init(storage: RefJson = .null, codingPath: [CodingKey] = [], boxer: Boxer) {
		self.storage = storage
		self.codingPath = codingPath
		self.boxer = boxer
	}
	
	func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
		let dict: DictClass<RefJson>
		switch storage.kind {
		case .object(let d):
			dict = d
		default:
			dict = DictClass()
			storage.kind = .object(dict)
		}
		let container = _KeyedContainer<Key>(codingPath: codingPath, boxer: boxer, json: dict)
		return KeyedEncodingContainer(container)
	}
	
	func unkeyedContainer() -> UnkeyedEncodingContainer {
		let array: ArrayClass<RefJson>
		switch storage.kind {
		case .array(let ar):
			array = ar
		default:
			array = ArrayClass()
			storage.kind = .array(array)
		}
		let container = _UnkeyedContainer(codingPath: codingPath, boxer: boxer, json: array)
		return container
	}
	
	func singleValueContainer() -> SingleValueEncodingContainer {
		let container = _SingleContainer(codingPath: codingPath, boxer: boxer, json: storage)
		return container
	}
	
}

fileprivate struct _KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
	var codingPath: [CodingKey]
	let json: DictClass<RefJson>
	var isEmpty: Bool { return json.dict.isEmpty }
	let boxer: Boxer
	
	init(codingPath: [CodingKey], boxer: Boxer, json: DictClass<RefJson> = DictClass()) {
		self.codingPath = codingPath
		self.boxer = boxer
		self.json = json
	}
	
	func encodeNil(forKey key: Key) throws {}
	
	func encode(_ value: Bool, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encode(value, codingPath: path)
	}
	
	mutating func encode(_ value: String, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encode(value, codingPath: path)
	}
	
	func encode(_ value: Double, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encode(value, codingPath: path)
	}
	
	func encode(_ value: Float, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encode(value, codingPath: path)
	}
	
	func encode(_ value: Int, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeSignedInt(value, codingPath: path)
	}
	
	func encode(_ value: Int8, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeSignedInt(value, codingPath: path)
	}
	
	func encode(_ value: Int16, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeSignedInt(value, codingPath: path)
	}
	
	func encode(_ value: Int32, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeSignedInt(value, codingPath: path)
	}
	
	func encode(_ value: Int64, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeSignedInt(value, codingPath: path)
	}
	
	func encode(_ value: UInt, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeUnsignedInt(value, codingPath: path)
	}
	
	func encode(_ value: UInt8, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeUnsignedInt(value, codingPath: path)
	}
	
	func encode(_ value: UInt16, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeUnsignedInt(value, codingPath: path)
	}
	
	func encode(_ value: UInt32, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeUnsignedInt(value, codingPath: path)
	}
	
	func encode(_ value: UInt64, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encodeUnsignedInt(value, codingPath: path)
	}
	
	func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
		let path = codingPath + [key]
		let newKey = boxer.key(key.stringValue, codingPath: path)
		json.dict[newKey] = try boxer.encode(value, codingPath: path)
	}
	
	func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
		var path = codingPath
		path.append(key)
		let container = _KeyedContainer<NestedKey>(codingPath: path, boxer: boxer)
		json.dict[key.stringValue] = RefJson(.object(container.json))
		return KeyedEncodingContainer(container)
	}
	
	func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
		var path = codingPath
		path.append(key)
		let container = _UnkeyedContainer(codingPath: path, boxer: boxer)
		json.dict[key.stringValue] = RefJson(.array(container.storage))
		return container
	}
	
	func superEncoder() -> Encoder {
		let key = PlainCodingKey("super")
		var path = codingPath
		path.append(key)
		let encoder = _Encoder(codingPath: path, boxer: boxer)
		json.dict[key.stringValue] = encoder.storage
		return encoder
	}
	
	func superEncoder(forKey key: Key) -> Encoder {
		var path = codingPath
		path.append(key)
		let encoder = _Encoder(codingPath: path, boxer: boxer)
		json.dict[key.stringValue] = encoder.storage
		return encoder
	}
	
}

fileprivate struct _UnkeyedContainer: UnkeyedEncodingContainer {
	var codingPath: [CodingKey]
	let storage: ArrayClass<RefJson>
	var count: Int { return storage.array.count }//+ nested.count }
	let boxer: Boxer
	//var nested: ContiguousArray<Container> = []
	
	init(codingPath: [CodingKey], boxer: Boxer, json: ArrayClass<RefJson> = ArrayClass()) {
		self.codingPath = codingPath
		self.boxer = boxer
		self.storage = json
	}
	
	func encodeNil() throws {}
	
	mutating func encode(_ value: Bool) throws {
		try storage.array.append(boxer.encode(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: String) throws {
		try storage.array.append(boxer.encode(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Double) throws {
		try storage.array.append(boxer.encode(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Float) throws {
		try storage.array.append(boxer.encode(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Int) throws {
		try storage.array.append(boxer.encodeSignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Int8) throws {
		try storage.array.append(boxer.encodeSignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Int16) throws {
		try storage.array.append(boxer.encodeSignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Int32) throws {
		try storage.array.append(boxer.encodeSignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: Int64) throws {
		try storage.array.append(boxer.encodeSignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: UInt) throws {
		try storage.array.append(boxer.encodeUnsignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	func encode(_ value: UInt8) throws {
		try storage.array.append(boxer.encodeUnsignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: UInt16) throws {
		try storage.array.append(boxer.encodeUnsignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: UInt32) throws {
		try storage.array.append(boxer.encodeUnsignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode(_ value: UInt64) throws {
		try storage.array.append(boxer.encodeUnsignedInt(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	mutating func encode<T: Encodable>(_ value: T) throws {
		try storage.array.append(boxer.encode(value, codingPath: codingPath + [PlainCodingKey(count)]))
	}
	
	func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
		var path = codingPath
		path.append(PlainCodingKey(count))
		let container = _KeyedContainer<NestedKey>(codingPath: path, boxer: boxer)
		storage.array.append(RefJson(.object(container.json)))
		return KeyedEncodingContainer(container)
	}
	
	func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
		var path = codingPath
		path.append(PlainCodingKey(count))
		let container = _UnkeyedContainer(codingPath: path, boxer: boxer)
		storage.array.append(RefJson(.array(container.storage)))
		return container
	}
	
	func superEncoder() -> Encoder {
		var path = codingPath
		path.append(PlainCodingKey(count))
		let encoder = _Encoder(codingPath: path, boxer: boxer)
		storage.array.append(encoder.storage)
		return encoder
	}
	
}

fileprivate final class _SingleContainer: SingleValueEncodingContainer {
	var codingPath: [CodingKey]
	let storage: RefJson
	let boxer: Boxer
	
	init(codingPath: [CodingKey] = [], boxer: Boxer, json: RefJson) {
		self.codingPath = codingPath
		self.boxer = boxer
		self.storage = json
	}
	
	func encodeNil() throws {
		storage.kind = boxer.encodeNil().kind
	}
	
	func encode(_ value: Bool) throws {
		storage.kind = try boxer.encode(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: String) throws {
		storage.kind = try boxer.encode(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Double) throws {
		storage.kind = try boxer.encode(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Float) throws {
		storage.kind = try boxer.encode(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Int) throws {
		storage.kind = try boxer.encodeSignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Int8) throws {
		storage.kind = try boxer.encodeSignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Int16) throws {
		storage.kind = try boxer.encodeSignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Int32) throws {
		storage.kind = try boxer.encodeSignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: Int64) throws {
		storage.kind = try boxer.encodeSignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: UInt) throws {
		storage.kind = try boxer.encodeUnsignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: UInt8) throws {
		storage.kind = try boxer.encodeUnsignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: UInt16) throws {
		storage.kind = try boxer.encodeUnsignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: UInt32) throws {
		storage.kind = try boxer.encodeUnsignedInt(value, codingPath: codingPath).kind
	}
	
	func encode(_ value: UInt64) throws {
		storage.kind = try boxer.encodeUnsignedInt(value, codingPath: codingPath).kind
	}
	
	func encode<T: Encodable>(_ value: T) throws {
		storage.kind = try boxer.encode(value, codingPath: codingPath).kind
	}
	
}

fileprivate struct Boxer {
	
	let userInfo: [CodingUserInfoKey : Any]
	let dateEncodingStrategy: CacheJSONEncoder.DateEncodingStrategy
	let keyEncodingStrategy: CacheJSONEncoder.KeyEncodingStrategy
	var cacheInfo: BoxerCacheInfo?
	
	init(userInfo: [CodingUserInfoKey : Any], dateEncodingStrategy: CacheJSONEncoder.DateEncodingStrategy, keyEncodingStrategy: CacheJSONEncoder.KeyEncodingStrategy, cacheInfo: BoxerCacheInfo?) {
		self.userInfo = userInfo
		self.dateEncodingStrategy = dateEncodingStrategy
		self.keyEncodingStrategy = keyEncodingStrategy
		self.cacheInfo = cacheInfo
	}
	
	func key(_ fromKey: String, codingPath: [CodingKey]) -> String {
		switch keyEncodingStrategy {
		case .useDefaultKeys:
			return fromKey
		case .convertToSnakeCase:
			return CacheJSONEncoder.KeyEncodingStrategy._convertToSnakeCase(fromKey)
		case .custom(let block):
			return block(codingPath)
		}
	}
	
	func encodeNil() -> RefJson {
		return .null
	}
	
	func encode(_ value: Bool, codingPath: [CodingKey]) throws -> RefJson {
		return .bool(value)
	}
	
	func encode(_ value: String, codingPath: [CodingKey]) throws -> RefJson {
		return .string(value)
	}
	
	func encode(_ value: Double, codingPath: [CodingKey]) throws -> RefJson {
		return .double(value)
	}
	
	func encode(_ value: Float, codingPath: [CodingKey]) throws -> RefJson {
		return .double(Double(value))
	}
	
	func encodeSignedInt<I: SignedBitPatternInitializable>(_ value: I, codingPath: [CodingKey]) throws -> RefJson {
		return .int(Int(value))
	}
	
	func encodeUnsignedInt<I: FixedWidthInteger & UnsignedInteger>(_ value: I, codingPath: [CodingKey]) throws -> RefJson {
		guard value <= Int.max else {
			throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Number <\(value)> does not fit in Int"))
		}
		return .int(Int(value))
	}
	
	func encodeDate(_ value: Date, to encoder: _Encoder) throws {
		switch dateEncodingStrategy {
		case .deferredFromDate: return try value.encode(to: encoder)
		case .secondsSince1970:
			try value.timeIntervalSince1970.encode(to: encoder)
		case .millisecondsSince1970:
			try (value.timeIntervalSince1970 * 1000).encode(to: encoder)
		case .iso8601:
			let result: String
			if #available(iOS 10.0, *) {
				result = _iso8601Formatter.string(from: value)
			} else {
				result = _iso8601DateFormatter.string(from: value)
			}
			try result.encode(to: encoder)
		case .formatted(let formatter):
			let result = formatter.string(from: value)
			try result.encode(to: encoder)
		case .custom(let transform):
			try transform(value, encoder)
		}
	}
	
	func encode<T: Encodable>(_ value: T, codingPath: [CodingKey]) throws -> RefJson {
		if let result = value as? RefJson { return result }
		let encoder = _Encoder(codingPath: codingPath, boxer: self)
		if let date = value as? Date {
			try encodeDate(date, to: encoder)
		}
		if let info = cacheInfo,
			let container = info.storagesContainer,
			!codingPath.isEmpty,
			let cacheKey = (value as? CacheReferenceable)?.cachePrimaryKey {
			let storage = container.anyStorage(of: T.self)
			try storage.setObject(value, forKey: cacheKey, referenced: (info.rootStorageName, info.rootKey))
			info.referenceKeys.dict[container.nameForStorage(of: T.self), default: []].insert(cacheKey)
			return .string(cacheKey)
		}
		try value.encode(to: encoder)
		return encoder.storage
	}
	
}

fileprivate final class ArrayClass<T>: ExpressibleByArrayLiteral {
	
	var array: [T] = []
	
	init(_ array: [T] = []) {
		self.array = array
	}
	
	init(arrayLiteral elements: T...) {
		self.array = elements
	}
	
}

fileprivate final class DictClass<T>: ExpressibleByDictionaryLiteral {
	
	var dict: [String: T] = [:]
	
	init(_ dict: [String: T] = [:]) {
		self.dict = dict
	}
	
	init(dictionaryLiteral elements: (String, T)...) {
		self.dict = [String: T](uniqueKeysWithValues: elements)
	}
	
}

fileprivate final class RefJson {
	
	enum Kind {
		case bool(Bool)
		case int(Int)
		case double(Double)
		case string(String)
		case array(ArrayClass<RefJson>)
		case object(DictClass<RefJson>)
		case null
	}
	
	static func bool(_ value: Bool) -> RefJson { return RefJson(.bool(value)) }
	static func int(_ value: Int) -> RefJson { return RefJson(.int(value)) }
	static func double(_ value: Double) -> RefJson { return RefJson(.double(value)) }
	static func string(_ value: String) -> RefJson { return RefJson(.string(value)) }
	static func array(_ value: [RefJson]) -> RefJson { return RefJson(.array(ArrayClass(value))) }
	static func object(_ value: [String: RefJson]) -> RefJson { return RefJson(.object(DictClass(value))) }
	static var null: RefJson { return RefJson(.null) }
	
	var kind: Kind
	
	init(_ kind: Kind) {
		self.kind = kind
	}
	
	var data: Data {
		var encoder = ProtobufJSONEncoder()
		putSelf(to: &encoder)
		return encoder.dataResult
	}
	
	func putSelf(to encoder: inout ProtobufJSONEncoder) {
		switch kind {
		case .object(let object):
			let separator = encoder.separator
			encoder.separator = nil
			encoder.openCurlyBracket()
			for (key, value) in object.dict {
				encoder.startField(name: key)
				value.putSelf(to: &encoder)
			}
			encoder.closeCurlyBracket()
			encoder.separator = separator
		case .array(let array):
			encoder.openSquareBracket()
			if let value = array.array.first {
				value.putSelf(to: &encoder)
				var index = 1
				while index < array.array.count {
					encoder.comma()
					array.array[index].putSelf(to: &encoder)
					index += 1
				}
			}
			encoder.closeSquareBracket()
		case .bool(let bool):     encoder.putBoolValue(value: bool)
		case .int(let int):       encoder.appendInt(value: Int64(int))
		case .double(let double): encoder.putDoubleValue(value: double)
		case .string(let string): encoder.putStringValue(value: string)
		case .null:				  break//encoder.putNullValue()
		}
	}
	
}

fileprivate struct BoxerCacheInfo {
	weak var storagesContainer: CacheContext?
	var rootKey: String
	var rootStorageName: String
	var referenceKeys: DictClass<Set<String>>
}
