//
//  PlainCodingKey.swift
//  JSON
//
//  Created by Данил Войдилов on 05/01/2019.
//

import Foundation

public struct PlainCodingKey: CodingKey, Hashable {
	public var stringValue: String
	public var intValue: Int?
	
	public init?(stringValue: String) { self.stringValue = stringValue }
	public init(_ stringValue: String) { self.stringValue = stringValue }
	public init(_ intValue: Int) {
		self.stringValue = "\(intValue)"
		self.intValue = intValue
	}
	public init(_ key: CodingKey) {
		self.stringValue = key.stringValue
		self.intValue = key.intValue
	}
	public init?(intValue: Int) {
		self.stringValue = "\(intValue)"
		self.intValue = intValue
	}
	
}


