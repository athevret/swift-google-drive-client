//
//  ExecuteScriptTests.swift
//  swift-google-drive-client
//
//  Created by Alban THEVRET on 11/05/2025.
//

import XCTest
@testable import GoogleDriveClient

final class ExecuteScriptTests: XCTestCase {

  func testExecuteScript() async throws {
    let credentials = Credentials(
      accessToken: "access-token-1",
      expiresAt: Date(),
      refreshToken: "refresh-token-1",
      tokenType: "token-type-1"
    )
    let httpRequests = ActorIsolated<[URLRequest]>([])
    let didRefreshToken = ActorIsolated(0)
    let executeScript = ExecuteScript.live(
      auth: {
        var auth = Auth.unimplemented()
        auth.refreshToken = {
          await didRefreshToken.withValue { $0 += 1 }
        }
        return auth
      }(),
      keychain: {
        var keychain = Keychain.unimplemented()
        keychain.loadCredentials = { credentials }
        return keychain
      }(),
      httpClient: .init { request in
        await httpRequests.withValue { $0.append(request) }
        return (
          """
          {
            "done": true,
            "response": {
              "result": "api response data"
            }
          }
          """.data(using: .utf8)!,
          HTTPURLResponse(
            url: URL(filePath: "/"),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      }
    )
    let params = ExecuteScript.Params(
      scriptId: "abcdefghijklmnopqrstuvwxyz0123456789",
      function: "apiFunction",
      args: ["arg1", "arg2"]
    )

    // Execute Google API function with parameters
    let result = try await executeScript(params)

    // Ensure token was refreshed
    await didRefreshToken.withValue {
      XCTAssertEqual($0, 1)
    }

    // Verify the http request encoding
    await httpRequests.withValue {
      var urlComponents = URLComponents()
      urlComponents.scheme = "https"
      urlComponents.host = "script.googleapis.com"
      urlComponents.path = "/v1/scripts/abcdefghijklmnopqrstuvwxyz0123456789:run"

      var expectedRequest = URLRequest(url: urlComponents.url!)
      expectedRequest.httpMethod = "POST"
      expectedRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
      expectedRequest.allHTTPHeaderFields = [
        "Authorization": "\(credentials.tokenType) \(credentials.accessToken)"
      ]

      let requestBody: [String: Any] = [
        "function": params.function,
        "parameters": params.args,
        "devMode": false
      ]
      expectedRequest.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

      XCTAssertEqual($0, [expectedRequest])
      XCTAssertEqual($0.first?.httpBody, expectedRequest.httpBody)
    }

    // Verify request result
    XCTAssertEqual(
      result, "{\"result\":\"api response data\"}".data(using: .utf8)!
    )
  }

  // MARK: DEACTIVATED test - No way to generate the invalidParams error
//  func testExecuteScriptInvalidParams() async throws {
//    let credentials = Credentials(
//      accessToken: "access-token-1",
//      expiresAt: Date(),
//      refreshToken: "refresh-token-1",
//      tokenType: "token-type-1"
//    )
//    let httpRequests = ActorIsolated<[URLRequest]>([])
//    let didRefreshToken = ActorIsolated(0)
//    let executeScript = ExecuteScript.live(
//      auth: {
//        var auth = Auth.unimplemented()
//        auth.refreshToken = {
//          await didRefreshToken.withValue { $0 += 1 }
//        }
//        return auth
//      }(),
//      keychain: {
//        var keychain = Keychain.unimplemented()
//        keychain.loadCredentials = { credentials }
//        return keychain
//      }(),
//      httpClient: .init { request in
//        await httpRequests.withValue { $0.append(request) }
//        return (
//          """
//          {
//            "done": true
//            "response": "api response data"
//          }
//          """.data(using: .utf8)!,
//          HTTPURLResponse(
//            url: URL(filePath: "/"),
//            statusCode: 200,
//            httpVersion: nil,
//            headerFields: nil
//          )!
//        )
//      }
//    )
//    let params = ExecuteScript.Params(
//      scriptId: "\u{000}#fragment%GG",
//      function: "apiFunction",
//      args: ["arg1", "arg2"]
//    )
//
//    // Execute Google API function with parameters
//    do {
//      _ = try await executeScript(params)
//
//      // Ensure an exception was raised
//      XCTFail("executeScript should have raised an error")
//    } catch let error as ExecuteScript.Error {
//      // Ensure invalidParams was raised
//      XCTAssertEqual(error, ExecuteScript.Error.invalidParams)
//    } catch {
//      XCTFail("Unexpected error: \(error)")
//    }
//  }

  func testExecuteScriptServerError() async throws {
    let executeScript = ExecuteScript.live(
      auth: {
        var auth = Auth.unimplemented()
        auth.refreshToken = {}
        return auth
      }(),
      keychain: {
        var keychain = Keychain.unimplemented()
        keychain.loadCredentials = {
          Credentials(
            accessToken: "",
            expiresAt: Date(),
            refreshToken: "",
            tokenType: ""
          )
        }
        return keychain
      }(),
      httpClient: .init { request in
        (
          "Error!!!".data(using: .utf8)!,
          HTTPURLResponse(
            url: URL(filePath: "/"),
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      }
    )
    let params = ExecuteScript.Params(
      scriptId: "abcdefghijklmnopqrstuvwxyz0123456789",
      function: "apiFunction",
      args: ["arg1", "arg2"]
    )

    do {
      // Execute Google API function with parameters
    let result = try await executeScript(params)
      XCTFail("Expected to throw error, got result: \(result)")
    } catch let error as ExecuteScript.Error {
      // Ensure invalidParams was raised
      XCTAssertEqual(
        error,
        ExecuteScript.Error.serveurError(
          statusCode: 500,
          data: "Error!!!".data(using: .utf8)!
        ),
        "Unexpected ExecuteScript error: \(error)"
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

  }

  func testExecuteScriptExecutionError() async throws {
    let credentials = Credentials(
      accessToken: "access-token-1",
      expiresAt: Date(),
      refreshToken: "refresh-token-1",
      tokenType: "token-type-1"
    )
    let httpRequests = ActorIsolated<[URLRequest]>([])
    let didRefreshToken = ActorIsolated(0)
    let executeScript = ExecuteScript.live(
      auth: {
        var auth = Auth.unimplemented()
        auth.refreshToken = {
          await didRefreshToken.withValue { $0 += 1 }
        }
        return auth
      }(),
      keychain: {
        var keychain = Keychain.unimplemented()
        keychain.loadCredentials = { credentials }
        return keychain
      }(),
      httpClient: .init { request in
        await httpRequests.withValue { $0.append(request) }
        return (
          """
          {
            "done": true,
            "error": {
              "code": 123,
              "message": "Error Message",
              "status": "Status",
              "details": []
            }
          }
          """.data(using: .utf8)!,
          HTTPURLResponse(
            url: URL(filePath: "/"),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      }
    )
    let params = ExecuteScript.Params(
      scriptId: "abcdefghijklmnopqrstuvwxyz0123456789",
      function: "apiFunction",
      args: ["arg1", "arg2"]
    )

    do {
      // Execute Google API function with parameters
    let result = try await executeScript(params)
      XCTFail("Expected to throw error, got result: \(result)")
    } catch let error as ExecuteScript.Error {
      // Ensure invalidParams was raised
      XCTAssertEqual(
        error,
        ExecuteScript.Error.scriptExecutionError(
          code: 123,
          message: "Error Message",
          status: "Status"),
        "Unexpected ExecuteScript error: \(error)"
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testExecuteScriptWhenNotAuthorized() async throws {
    let executeScript = ExecuteScript.live(
      auth: {
        var auth = Auth.unimplemented()
        auth.refreshToken = {}
        return auth
      }(),
      keychain: {
        var keychain = Keychain.unimplemented()
        keychain.loadCredentials = { nil }
        return keychain
      }(),
      httpClient: .unimplemented()
    )
    let params = ExecuteScript.Params(
      scriptId: "abcdefghijklmnopqrstuvwxyz0123456789",
      function: "apiFunction",
      args: ["arg1", "arg2"]
    )

    // Execute Google API function with parameters
    do {
      _ = try await executeScript(params)

      // Ensure an exception was raised
      XCTFail("executeScript should have raised an error")
    } catch let error as ExecuteScript.Error {
      // Ensure invalidParams was raised
      XCTAssertEqual(error, ExecuteScript.Error.notAuthorized)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
