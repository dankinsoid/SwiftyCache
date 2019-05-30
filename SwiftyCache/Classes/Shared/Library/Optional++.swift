//
//  Optional++.swift
//  RxTableView
//
//  Created by Данил Войдилов on 06/04/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation

postfix operator ~!

protocol OptionalProtocol {
	associatedtype Wrapped
	func unwrap(catch error: Error) throws -> Wrapped
}

extension Optional: OptionalProtocol {
	
	func unwrap(catch error: Error = UnwrapError.foundNilWhenExpectedValue) throws -> Wrapped {
		switch self {
		case .some(let wrapped): return wrapped
		case .none: 			 throw  error
		}
	}
	
}

postfix func ~!<X>(x: X?) throws -> X {
	return try x.unwrap()
}

enum UnwrapError: String, LocalizedError {
	case foundNilWhenExpectedValue
}
