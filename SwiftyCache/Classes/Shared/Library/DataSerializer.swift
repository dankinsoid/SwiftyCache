import Foundation

/// Convert to and from data
enum DataSerializer {
	
	static func serialize<T>(object: T, info: DiskEntity, transformer: Transformer<T>) throws -> Data {
		let data = try transformer.toData(object)
		return try serialize(data: data, info: info)
	}
	
	static func serialize(data: Data, info: DiskEntity) throws -> Data {
		var encoder = ProtobufJSONEncoder()
		info.encode(to: &encoder)
		encoder.comma()
		encoder.append(utf8Data: data)
		return encoder.dataResult
	}
	
	static func deserialize<T>(data: Data, transformer: Transformer<T>) throws -> (DiskEntity, T) {
		return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> (DiskEntity, T) in
			let source = bytes.bindMemory(to: UInt8.self)
			var scanner = JSONScanner(source: source, messageDepthLimit: .max)
			let info = try DiskEntity(scanner: &scanner)
			try scanner.skipRequiredComma()
			let value = try transformer.fromData(data.suffix(from: scanner.currentIndex))
			return (info, value)
		}
	}
	
	static func getKey(from data: Data) throws -> String {
		return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> String in
			let source = bytes.bindMemory(to: UInt8.self)
			var scanner = JSONScanner(source: source, messageDepthLimit: .max)
			return try scanner.nextQuotedString()
		}
	}
	
	static func getInfo(from data: Data) throws -> DiskEntity {
		return try DiskEntity(from: data)
	}
	
}

struct DiskEntity: Codable {
	var key: String
	var referencedKeys: [String: Set<String>]
	var removeIfNoRef: Bool?
	
	init(key: String, referencedKeys: [String: Set<String>] = [:], removeIfNoRef: Bool? = nil) {
		self.key = key
		self.referencedKeys = referencedKeys
		self.removeIfNoRef = removeIfNoRef
	}
	
	init(scanner: inout JSONScanner) throws {
		key = try scanner.nextQuotedString()
		try scanner.skipRequiredComma()
		referencedKeys = try scanner.nextSetDict()
		try scanner.skipRequiredComma()
		do {
			removeIfNoRef = try scanner.nextBool()
		} catch {
			_ = scanner.skipOptionalNull()
		}
	}
	
	init(from data: Data) throws {
		self = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> DiskEntity in
			let source = bytes.bindMemory(to: UInt8.self)
			var scanner = JSONScanner(source: source, messageDepthLimit: .max)
			return try DiskEntity(scanner: &scanner)
		}
	}
	
	func encode(to encoder: inout ProtobufJSONEncoder) {
		encoder.putStringValue(value: key)
		encoder.comma()
		encoder.putSetDict(referencedKeys)
		encoder.comma()
		if let rem = removeIfNoRef {
			encoder.putBoolValue(value: rem)
		} else {
			encoder.putNullValue()
		}
	}
	
	func encode() -> Data {
		var encoder = ProtobufJSONEncoder()
		encode(to: &encoder)
		return encoder.dataResult
	}
	
}

extension JSONScanner {
	
	fileprivate mutating func nextSetDict() throws -> [String: Set<String>] {
		var object: [String: Set<String>] = [:]
		try skipRequiredObjectStart()
		if !skipOptionalObjectEnd() {
			let key = try nextQuotedString()
			try skipRequiredColon()
			let value = try nextStringSet()
			object[key] = value
			while !skipOptionalObjectEnd() {
				try skipRequiredComma()
				let key = try nextQuotedString()
				try skipRequiredColon()
				let value = try nextStringSet()
				object[key] = value
			}
		}
		return object
	}
	
	fileprivate mutating func nextStringSet() throws -> Set<String> {
		var array: Set<String> = []
		try skipRequiredArrayStart()
		if !skipOptionalArrayEnd() {
			try array.insert(nextQuotedString())
			while !skipOptionalArrayEnd() {
				try skipRequiredComma()
				try array.insert(nextQuotedString())
			}
		}
		return array
	}
}

extension ProtobufJSONEncoder {
	
	fileprivate mutating func putSetDict(_ dict: [String: Set<String>]) {
		separator = nil
		openCurlyBracket()
		for (key, value) in dict {
			startField(name: key)
			putStringSet(value)
		}
		closeCurlyBracket()
	}
	
	fileprivate mutating func putStringSet(_ set: Set<String>) {
		openSquareBracket()
		if let value = set.first {
			putStringValue(value: value)
			var index = set.index(after: set.startIndex)
			while index < set.endIndex {
				comma()
				putStringValue(value: set[index])
				set.formIndex(after: &index)
			}
		}
		closeSquareBracket()
	}
	
}
