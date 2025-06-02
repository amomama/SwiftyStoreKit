//
// ProductsInfoController.swift
// SwiftyStoreKit
//
// Copyright (c) 2015 Andrea Bizzotto (bizz84@gmail.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import StoreKit

protocol InAppProductRequestBuilder: AnyObject {
    func request(productIds: Set<String>, callback: @escaping InAppProductRequestCallback) -> InAppProductRequest
}

class InAppProductQueryRequestBuilder: InAppProductRequestBuilder {
    
    func request(productIds: Set<String>, callback: @escaping InAppProductRequestCallback) -> InAppProductRequest {
        return InAppProductQueryRequest(productIds: productIds, callback: callback)
    }
}

class ProductsInfoController: NSObject {

    struct InAppProductQuery {
        let request: InAppProductRequest
        var completionHandlers: [InAppProductRequestCallback]
    }
    
    let inAppProductRequestBuilder: InAppProductRequestBuilder
    init(inAppProductRequestBuilder: InAppProductRequestBuilder = InAppProductQueryRequestBuilder()) {
        self.inAppProductRequestBuilder = inAppProductRequestBuilder
    }
    
    // As we can have multiple inflight requests, we store them in a dictionary by product ids
    private var inflightRequestsStorage: [Set<String>: InAppProductQuery] = [:]
    private let requestsQueue = DispatchQueue(label: "inflightRequestsQueue", attributes: .concurrent)

    @discardableResult
    func retrieveProductsInfo(_ productIds: Set<String>, completion: @escaping (RetrieveResults) -> Void) -> InAppProductRequest {
        var returnedRequest: InAppProductRequest!
        
        requestsQueue.sync(flags: .barrier) {
            if inflightRequestsStorage[productIds] == nil {
                // No existing request → create new
                let request = inAppProductRequestBuilder.request(productIds: productIds) { results in
                    self.requestsQueue.sync(flags: .barrier) {
                        if let query = self.inflightRequestsStorage[productIds] {
                            for completion in query.completionHandlers {
                                completion(results)
                            }
                            self.inflightRequestsStorage[productIds] = nil
                        } else {
                            // should not get here, but if it does it seems reasonable to call the outer completion block
                            completion(results)
                        }
                    }
                }
                inflightRequestsStorage[productIds] = InAppProductQuery(request: request, completionHandlers: [completion])
                request.start()
                returnedRequest = request
            } else {
                var query = inflightRequestsStorage[productIds]!
                query.completionHandlers.append(completion)
                inflightRequestsStorage[productIds] = query
                
                if query.request.hasCompleted, let cached = query.request.cachedResults {
                    query.completionHandlers.forEach { $0(cached) }
                    inflightRequestsStorage[productIds] = nil
                }
                returnedRequest = query.request
            }
        }
        return returnedRequest
    }
}
