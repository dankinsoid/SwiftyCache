//
//  Optional++.swift
//  RxTableView
//
//  Created by Данил Войдилов on 06/04/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation

postfix operator ~!

public protocol OptionalProtocol {
	associatedtype Wrapped
	func unwrap(catch error: Error) throws -> Wrapped
}

extension Optional: OptionalProtocol {
	
	public func unwrap(catch error: Error = UnwrapError.foundNilWhenExpectedValue) throws -> Wrapped {
		switch self {
		case .some(let wrapped): return wrapped
		case .none: 			 throw  error
		}
	}
	
}

public postfix func ~!<X>(x: X?) throws -> X {
	return try x.unwrap()
}

public enum UnwrapError: String, LocalizedError {
	case foundNilWhenExpectedValue
}
