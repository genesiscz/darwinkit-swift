import Foundation
import Testing
@testable import DarwinKitCore
import DarwinKitObjC

// Regression coverage for the ObjC @try/@catch shim.
//
// The bug: on macOS 26, an Apple typed accessor inside
// AppleRemindersProvider.mapReminder raised NSUnknownKeyException via KVC.
// Swift's `try`/`do/catch` does not catch NSExceptions, so the unwind walked
// past every Swift frame straight to abort(), killing the JSON-RPC daemon.
//
// The shim must convert any NSException raised inside dispatch into a
// JSON-RPC error frame (code -32000, "internal exception: <name>: <reason>").
// We can't easily reproduce the Apple-side crash in tests (it needs Reminders
// authorization and macOS 26), so these tests verify the defense itself:
// raising a synthetic NSException through the same code path that production
// uses must come out the other side as a JSON-RPC error, not an abort.
@Suite("ObjC Exception Shim")
struct ObjCExceptionShimTests {

    @Test("catchException succeeds when block does not raise")
    func catchExceptionPassthrough() {
        var ran = false
        let success: Bool
        do {
            try DarwinKitObjC.catchException {
                ran = true
            }
            success = true
        } catch {
            success = false
        }
        #expect(success)
        #expect(ran)
    }

    @Test("catchException converts NSException to NSError with name and reason")
    func catchExceptionNSException() {
        var caught: NSError? = nil
        do {
            try DarwinKitObjC.catchException {
                NSException(
                    name: NSExceptionName("NSUnknownKeyException"),
                    reason: "this is a test reason",
                    userInfo: nil
                ).raise()
            }
            Issue.record("expected catchException to throw")
        } catch {
            caught = error as NSError
        }

        let ns = try! #require(caught)
        #expect(ns.domain == DarwinKitObjCExceptionDomain)
        #expect(ns.userInfo[DarwinKitObjCExceptionNameKey] as? String == "NSUnknownKeyException")
        #expect(ns.userInfo[DarwinKitObjCExceptionReasonKey] as? String == "this is a test reason")
    }

    @Test("JsonRpcError.objcException maps to code -32000")
    func objcExceptionErrorBody() {
        let err = JsonRpcError.objcException(name: "NSUnknownKeyException", reason: "no such key foo")
        let body = err.body
        #expect(body.code == -32000)
        #expect(body.message == "internal exception: NSUnknownKeyException: no such key foo")
    }
}
