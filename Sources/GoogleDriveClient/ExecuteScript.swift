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
    case invalidParams
    case serveurError(statusCode: Int?, data: Data)
    case invalidResponse
    case scriptExecutionError(code: Int?, message: String?, status: String?)

    public static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
      case (.notAuthorized, .notAuthorized),
        (.invalidParams, .invalidParams),
        (.invalidResponse, .invalidResponse):
        return true
      case (.serveurError(let lhsSC, let lhsD), .serveurError(let rhsSC, let rhsD)):
        return lhsSC == rhsSC && lhsD == rhsD
        case (.scriptExecutionError(let lhsC, let lhsM, let lhsS),
            .scriptExecutionError(let rhsC, let rhsM, let rhsS)):
        return lhsC == rhsC && lhsM == rhsM && lhsS == rhsS
      default:
        return false
      }
    }

    var localizedDescription: String {
      switch self {
      case .notAuthorized:
        return "Not authorized"
      case .invalidParams:
        return "Invalid parameter"
      case .serveurError(let statusCode, _):
        return "Serveur error (\(statusCode ?? 0))"
      case .invalidResponse:
        return "Invalid API response"
      case .scriptExecutionError(let code, let message, let status):
        return "Script execution error: \(message ?? "nil")(\(code ?? 0)), Status: \(status ?? "nil")"
      }
    }
  }

  // Script Error Structure
  struct ErrorData: Decodable {
    let code: Int
    let message: String
    let status: String
    let details: [ErrorDetail]?

    struct ErrorDetail: Decodable {
      let typeUrl: String?
      let scriptStackTraceElements: [StackTraceElement]?
      let errorMessage: String?
      let errorType: String?

      private enum CodingKeys: String, CodingKey {
        // swiftlint:disable:previous nesting
        case typeUrl = "@type"
        case scriptStackTraceElements
        case errorMessage
        case errorType
      }

      struct StackTraceElement: Decodable {
        let function: String
        let lineNumber: Int
      }
    }
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
  /// Execute the request and process returned data
  /// Decode and check generic Apps Scrpt (deployed as Executable API) response
  /// Successfull response syntax:
  /// `{
  /// `  "done": true,
  /// `  "response": {
  /// `    "result": <function result - not processed>
  /// `  }
  /// `}
  /// Error response syntax (returned as an scriptExecutionError) :
  /// `{
  /// `  "done": false,
  /// `  "error": {
  /// `    "code": Int,       // returned in .scriptExecutionError
  /// `    "message": String, // returned in .scriptExecutionError
  /// `    "status": String,  // returned in .scriptExecutionError
  /// `    "details": [       // not processed nor returned
  /// `      {
  /// `        "@type": String,
  /// `        "errorMessage": String,
  /// `        "errorType": String
  /// `        "scriptStackTraceElements": [
  /// `          {
  /// `            "function": String,
  /// `            "lineNumber": Int
  /// `          }
  /// `        ]
  /// `      }
  /// `    ]
  /// `  }
  /// `}`
  /// - Returns: The json data returned by the Apps Script function.
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

      // Prepare http request
      let request: URLRequest = try {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "script.googleapis.com"
        components.path = "/v1/scripts/\(params.scriptId):run"

        guard let url = components.url else {
          throw Error.invalidParams
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
          "\(credentials.tokenType) \(credentials.accessToken)",
          forHTTPHeaderField: "Authorization"
        )

        let requestBody: [String: Any] = [
          "function": params.function,
          "parameters": params.args,
          "devMode": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        return request
      }()

      // Execute http request
      let (responseData, response) = try await httpClient.data(for: request)

      // Check http request status code
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      guard let statusCode, (200..<300).contains(statusCode) else {
        throw Error.serveurError(statusCode: statusCode, data: responseData)
      }

      // Decode and check response
      guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
        throw Error.invalidResponse
      }

      // Send back function execution error as exception
      if let errorDict = json["error"] as? [String: Any] {
        let code = errorDict["code"] as? Int
        let message = errorDict["message"] as? String
        let status = errorDict["status"] as? String

        throw Error.scriptExecutionError(
          code: code,
          message: message,
          status: status
        )
      }

      // Send back function result as json extract ("result")
      if let responseDict = json["response"] as? [String: Any] {
        return try JSONSerialization.data(withJSONObject: responseDict as Any, options: [])
      } else {
        throw Error.invalidResponse
      }
    }
  }
}
