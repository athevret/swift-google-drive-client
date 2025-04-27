//
//  ExecuteScript.swift
//  swift-google-drive-client
//
//  Created by Alban THEVRET on 25/04/2025.
//

import Foundation

public struct ExecuteScript: Sendable {
  public struct Params: Sendable, Equatable {
    public init(
      scriptId: String,
      function: String,
      args: [String] = []
    ) {
      self.scriptId = scriptId
      self.function = function
      self.args = args
    }

    public var scriptId: String
    public var function: String
    public var args: [String]
  }

  public enum Error: Swift.Error, Sendable, Equatable {
    case notAuthorized
    case response(statusCode: Int?, data: Data)
  }

  public typealias Run = @Sendable (Params) async throws -> Data

  public init(run: @escaping Run) {
    self.run = run
  }

  public var run: Run

  public func callAsFunction(_ params: Params) async throws -> Data {
    try await run(params)
  }

  public func callAsFunction(
    scriptId: String,
    function: String,
    args: [String] = []
  ) async throws -> Data {
    try await run(.init(
      scriptId: scriptId,
      function: function,
      args: args
    ))
  }
}

extension ExecuteScript {
  public static func live(
    auth: Auth,
    keychain: Keychain,
    httpClient: HTTPClient
  ) -> ExecuteScript {
    ExecuteScript { params in
      try await auth.refreshToken()

      guard let credentials = await keychain.loadCredentials() else {
        throw Error.notAuthorized
      }

      let request: URLRequest = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "script.googleapis.com"
        components.path = "/v1/scripts/\(params.scriptId):run"
        print("Components: \(components)")

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
          "\(credentials.tokenType) \(credentials.accessToken)",
          forHTTPHeaderField: "Authorization"
        )
        print("Authorization: \(credentials.tokenType) \(credentials.accessToken)")

        let requestBody: [String: Any] = [
          "function": params.function,
          "parameters": params.args,
          "devMode": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        return request
      }()

      let (responseData, response) = try await httpClient.data(for: request)
      let statusCode = (response as? HTTPURLResponse)?.statusCode

      guard let statusCode, (200..<300).contains(statusCode) else {
        throw Error.response(statusCode: statusCode, data: responseData)
      }

      return responseData
    }
  }
}
