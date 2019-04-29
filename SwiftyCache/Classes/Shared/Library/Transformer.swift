import Foundation

public class Transformer<T> {
	public let toData: (T) throws -> Data
	public let fromData: (Data) throws -> T
	
	public init(toData: @escaping (T) throws -> Data, fromData: @escaping (Data) throws -> T) {
		self.toData = toData
		self.fromData = fromData
	}
}
