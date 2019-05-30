//
//  Int++.swift
//  Coders
//
//  Created by Данил Войдилов on 23/12/2018.
//  Copyright © 2018 daniil. All rights reserved.
//

import Foundation

protocol SignedBitPatternInitializable: FixedWidthInteger, SignedInteger
where Self.Magnitude: UnsignedBitPatternInitializable, Self.Magnitude.Signed == Self {
	init(bitPattern: Magnitude)
}

protocol UnsignedBitPatternInitializable where Signed.Magnitude == Self {
	associatedtype Signed: SignedBitPatternInitializable
	init(bitPattern: Signed)
}

extension Int: SignedBitPatternInitializable {}
extension Int8: SignedBitPatternInitializable {}
extension Int16: SignedBitPatternInitializable {}
extension Int32: SignedBitPatternInitializable {}
extension Int64: SignedBitPatternInitializable {}

extension UInt: UnsignedBitPatternInitializable { typealias Signed = Int }
extension UInt8: UnsignedBitPatternInitializable { typealias Signed = Int8 }
extension UInt16: UnsignedBitPatternInitializable { typealias Signed = Int16 }
extension UInt32: UnsignedBitPatternInitializable { typealias Signed = Int32 }
extension UInt64: UnsignedBitPatternInitializable { typealias Signed = Int64 }

extension Int {
	
	var bitPattern: UInt64 {
		return UInt64(self < 0 ? Magnitude.max - Magnitude(~self) : Magnitude(self))
	}
	
}

extension Int32 {
	
	var bitPattern: UInt32 {
		return self < 0 ? Magnitude.max - Magnitude(~self) : Magnitude(self)
	}
	
}
