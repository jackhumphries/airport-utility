import XCTest

@testable import AirPortUtilityCore

final class DiskInventoryParserTests: XCTestCase {
  func testDiskInventoryDiagnosticsExposeFieldStructureWithoutUUIDValue() {
    let json = """
      {"settings":{"MaSt":{"decoded":{"disks":[{"partitions":[{
        "deviceName":"dk2","name":"Data","uuid":"secret-uuid",
        "capacityBlocks":123,"availableBlocks":45
      }]}]}}}}
      """

    let summary = DiskInventoryParser.diagnosticFieldSummary(stdout: json)

    XCTAssertTrue(summary.contains("diskInventory.decoded.disks[0].partitions[0].capacityBlocks=<number>"))
    XCTAssertTrue(summary.contains("diskInventory.decoded.disks[0].partitions[0].availableBlocks=<number>"))
    XCTAssertTrue(summary.contains("diskInventory.decoded.disks[0].partitions[0].uuid=<string>"))
    XCTAssertFalse(summary.contains("secret-uuid"))
  }

  func testParsedDiskDiagnosticsReportMissingCapacity() {
    let record = DiskRecord(
      deviceName: "dk2", name: "Data", format: "HFS", uuid: "secret-uuid",
      size: nil, sizeFree: nil, builtIn: true)

    let summary = DiskInventoryParser.diagnosticRecordSummary([record])

    XCTAssertTrue(summary.contains("device=dk2"))
    XCTAssertTrue(summary.contains("name=Data"))
    XCTAssertTrue(summary.contains("size=<missing>"))
    XCTAssertTrue(summary.contains("sizeFree=<missing>"))
    XCTAssertFalse(summary.contains("secret-uuid"))
  }

  func testParsesTypedDecimalDiskSizesSeenOnModernTimeCapsule() {
    let json = """
      {"decoded":[{"deviceName":"wd0","builtin":true,"partitions":[{
        "deviceName":"dk2","name":"Data","format":"hfs",
        "size":{"type":"uint64","decimal":"953674","width":8},
        "sizeFree":{"type":"uint64","decimal":"474783","width":8}
      }]}]}
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.first?.size, 999_999_668_224)
    XCTAssertEqual(records.first?.sizeFree, 497_846_059_008)
  }

  func testDiskMetricDiagnosticsIncludeObservedNumericAndSmartValues() {
    let json = """
      {"decoded":[{"blockSize":{"decimal":"512"},"smartStatus":"verified",
        "partitions":[{"size":{"decimal":"953674"},"sizeFree":{"decimal":"474783"}}]
      }]}
      """

    let summary = DiskInventoryParser.diagnosticMetricSummary(stdout: json)

    XCTAssertTrue(summary.contains("blockSize.decimal=512"))
    XCTAssertTrue(summary.contains("smartStatus=verified"))
    XCTAssertTrue(summary.contains("partitions[0].size.decimal=953674"))
    XCTAssertTrue(summary.contains("partitions[0].sizeFree.decimal=474783"))
    XCTAssertEqual(DiskInventoryParser.smartStatuses(stdout: json), ["verified"])
  }
  func testDiskInventoryEmptyStateDoesNotExposeMaStRefreshInstruction() {
    XCTAssertEqual(
      DiskInventoryList.emptyStateText(didLoadInventory: false, isLoading: true),
      "Loading disk information..."
    )
    XCTAssertEqual(
      DiskInventoryList.emptyStateText(didLoadInventory: true, isLoading: false),
      "No disk partitions found."
    )
    XCTAssertEqual(
      DiskInventoryList.emptyStateText(didLoadInventory: false, isLoading: false),
      "No disk information loaded."
    )
  }

  func testPendingDiskInventoryRefreshPlaceholderIsNotLogged() {
    let message = AirportAppModel.diskInventoryRefreshSkippedMessage(
      for: "Refresh to load disk inventory from MaSt.")

    XCTAssertNil(message)
  }

  func testWrappedPendingDiskInventoryRefreshPlaceholderIsNotLogged() {
    let message = AirportAppModel.diskInventoryRefreshSkippedMessage(
      for: "Command failed: Refresh to load disk inventory from MaSt.\n")

    XCTAssertNil(message)
  }

  func testFriendlyPendingDiskInventoryMessageIsNotLogged() {
    let message = AirportAppModel.diskInventoryRefreshSkippedMessage(
      for: "Disk information is not available yet.")

    XCTAssertNil(message)
  }

  func testDiskInventoryRefreshErrorDoesNotExposeRawSettingName() {
    let message = AirportAppModel.diskInventoryRefreshSkippedMessage(
      for: "MaSt read failed: decoder error")

    XCTAssertEqual(
      message, "Disk inventory refresh skipped: disk inventory read failed: decoder error")
    XCTAssertFalse(message?.contains("MaSt") == true)
  }

  func testUserFacingErrorDoesNotExposeRawDiskInventorySettingName() {
    let message = AirportAppModel.userFacingErrorDescription(
      "MaSt read failed: decoder error")

    XCTAssertEqual(message, "disk inventory read failed: decoder error")
    XCTAssertFalse(message.contains("MaSt"))
  }

  func testUserFacingCommandOutputDoesNotExposeRawDiskInventorySettingName() {
    let output = AirportAppModel.userFacingCommandOutput(
      "Archive Disk: MaSt read failed: decoder error")

    XCTAssertEqual(output, "Archive Disk: disk inventory read failed: decoder error")
    XCTAssertFalse(output.contains("MaSt"))
  }

  func testUserFacingErrorDoesNotExposePendingDiskInventoryInstruction() {
    let message = AirportAppModel.userFacingErrorDescription(
      "Command failed: Refresh to load disk inventory from MaSt.")

    XCTAssertEqual(message, "Disk information is not available yet.")
  }

  func testUserFacingCommandOutputDoesNotExposePendingDiskInventoryInstruction() {
    let output = AirportAppModel.userFacingCommandOutput(
      "Archive Disk: Command failed.\nRefresh to load disk inventory from MaSt.\n")

    XCTAssertEqual(output, "Disk information is not available yet.")
  }

  func testUserFacingCommandOutputRemovesPendingInventoryLineFromMixedSuccessOutput() {
    let output = AirportAppModel.userFacingCommandOutput(
      "syNm: changed\nRefresh to load disk inventory from MaSt.\n")

    XCTAssertEqual(output, "syNm: changed\n")
    XCTAssertFalse(output.contains("Refresh to load disk inventory"))
    XCTAssertFalse(output.contains("MaSt"))
  }

  func testLogSanitizerRemovesPendingInventoryLineFromMixedSuccessOutput() {
    let output = AirportAppModel.sanitizedLogMessage(
      "$ airport_backend.py --setting syNm\nsyNm: changed\nRefresh to load disk inventory from MaSt.\n"
    )

    XCTAssertEqual(output, "$ airport_backend.py --setting syNm\nsyNm: changed")
    XCTAssertFalse(output.contains("Refresh to load disk inventory"))
    XCTAssertFalse(output.contains("MaSt"))
  }

  func testPendingDiskInventoryDetectionToleratesPunctuationAndCase() {
    let message = AirportAppModel.userFacingErrorDescription(
      "COMMAND FAILED: refresh-to-load disk_inventory from mast!")

    XCTAssertEqual(message, "Disk information is not available yet.")
  }

  func testLogSanitizerRemovesPendingDiskInventoryInstruction() {
    XCTAssertEqual(
      AirportAppModel.sanitizedLogMessage("Refresh to load disk inventory from MaSt."),
      ""
    )
    XCTAssertEqual(
      AirportAppModel.sanitizedLogMessage(
        "Command failed: Refresh to load disk inventory from MaSt.\n"
      ),
      ""
    )
    XCTAssertEqual(
      AirportAppModel.sanitizedLogMessage(
        "Error: Command failed: Refresh to load disk inventory from MaSt."
      ),
      "Error: Disk information is not available yet."
    )
    XCTAssertEqual(
      AirportAppModel.sanitizedLogMessage(
        "Identity refresh failed: Command failed: Refresh to load disk inventory from MaSt."
      ),
      ""
    )
    XCTAssertEqual(
      AirportAppModel.sanitizedLogMessage("MaSt read failed: decoder error"),
      "disk inventory read failed: decoder error"
    )
  }

  @MainActor func testFailedDiskInventoryRefreshPreservesLastGoodInventory() {
    let model = AirportAppModel()
    let record = DiskRecord(
      deviceName: "dk2",
      name: "Data",
      format: "HFS",
      uuid: "11111111111111111111111111111111",
      size: 1000,
      sizeFree: 500,
      builtIn: true)

    model.applyDiskInventoryRefreshResult((raw: "loaded inventory", records: [record]))
    model.applyDiskInventoryRefreshResult(nil)

    XCTAssertEqual(model.disks.rawInventory, "loaded inventory")
    XCTAssertEqual(model.disks.inventory, [record])
    XCTAssertTrue(model.disks.didLoadInventory)
  }

  @MainActor func testPendingDiskInventoryPlaceholderPreservesLastGoodInventory() {
    let model = AirportAppModel()
    let record = DiskRecord(
      deviceName: "dk2",
      name: "Data",
      format: "HFS",
      uuid: "11111111111111111111111111111111",
      size: 1000,
      sizeFree: 500,
      builtIn: true)

    model.applyDiskInventoryRefreshResult((raw: "loaded inventory", records: [record]))
    model.applyDiskInventoryRefreshResult(
      (
        raw: "Refresh to load disk inventory from MaSt.",
        records: []
      ))

    XCTAssertEqual(model.disks.rawInventory, "loaded inventory")
    XCTAssertEqual(model.disks.inventory, [record])
    XCTAssertTrue(model.disks.didLoadInventory)
  }

  @MainActor func testPendingDiskInventoryPlaceholderLeavesEmptyInventoryUnloaded() {
    let model = AirportAppModel()

    model.applyDiskInventoryRefreshResult(
      (
        raw: "Refresh to load disk inventory from MaSt.",
        records: []
      ))

    XCTAssertEqual(model.disks.rawInventory, "")
    XCTAssertEqual(model.disks.inventory, [])
    XCTAssertFalse(model.disks.didLoadInventory)
  }

  func testParsesMaStJSONAndByteObjects() {
    let json = """
      {
        "value": "CFB0...",
        "decoded": {
          "disks": [
            {
              "deviceName": "wd0",
              "builtIn": true,
              "partitions": [
                {
                  "deviceName": "dk2",
                  "name": {"type":"bytes","length":22,"hex":"4a61636b27732054696d652043617073756c6520486f6d65","text":"Jack's Time Capsule Home"},
                  "format": "HFS",
                  "uuid": {"type":"bytes","length":16,"hex":"adabbc6e09e0579081f8444e687f35b9"},
                  "size": 998000,
                  "sizeFree": 900000
                }
              ]
            }
          ]
        }
      }
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.count, 1)
    XCTAssertFalse(records.contains { $0.deviceName == "wd0" || $0.name == "wd0" })
    XCTAssertTrue(
      records.contains { record in
        record.name == "Jack's Time Capsule Home" && record.deviceName == "dk2"
          && record.format == "HFS" && record.uuid == "adabbc6e09e0579081f8444e687f35b9"
          && record.size == 1_046_478_848_000 && record.sizeFree == 943_718_400_000
          && record.builtIn
      })
  }

  func testParsesMaStSizesAsMebibyteAllocationUnits() {
    let json = """
      [
        {
          "deviceName": "wd0",
          "builtin": true,
          "partitions": [
            {
              "deviceName": "dk2",
              "name": "Data",
              "format": "hfs",
              "uuid": {"hex": "1343746ea33b5473a8adf43b75e5d004", "length": 16},
              "size": 474891,
              "sizeFree": 474783
            }
          ]
        },
        {
          "deviceName": "sd0",
          "partitions": [
            {
              "deviceName": "dk3",
              "name": "Untitled 2",
              "format": "hfs",
              "uuid": {"hex": "98cd04958940504da7b6e80f87996906", "length": 16},
              "size": 1907368,
              "sizeFree": 1906555
            }
          ]
        }
      ]
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.map(\.name), ["Data", "Untitled 2"])
    XCTAssertEqual(records.map(\.sizeFree), [497_846_059_008, 1_999_167_815_680])
    XCTAssertEqual(records.map(\.size), [497_959_305_216, 2_000_020_307_968])
    XCTAssertEqual(records.map(\.builtIn), [true, false])
  }

  func testSingleUnlabeledDiskInventoryDefaultsToBuiltInDisk() {
    let json = """
      [
        {
          "deviceName": "sd0",
          "partitions": [
            {
              "deviceName": "dk2",
              "name": "Untitled 2",
              "format": "hfs",
              "uuid": {"hex": "98cd04958940504da7b6e80f87996906", "length": 16}
            }
          ]
        }
      ]
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.map(\.name), ["Untitled 2"])
    XCTAssertEqual(records.map(\.builtIn), [true])
  }

  func testExplicitExternalDiskInventoryKeepsExternalClassification() {
    let json = """
      [
        {
          "deviceName": "sd0",
          "builtIn": false,
          "partitions": [
            {
              "deviceName": "dk3",
              "name": "USB Archive Disk",
              "format": "hfs",
              "uuid": {"hex": "22222222222222222222222222222222", "length": 16}
            }
          ]
        }
      ]
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.map(\.name), ["USB Archive Disk"])
    XCTAssertEqual(records.map(\.builtIn), [false])
  }

  func testParsesOnlyPartitionsWhenDiskHasMultiplePartitions() {
    let json = """
      {
        "decoded": {
          "disks": [
            {
              "deviceName": "wd0",
              "name": "wd0",
              "builtIn": true,
              "partitions": [
                {
                  "deviceName": "dk2",
                  "name": "Data",
                  "format": "HFS",
                  "uuid": "11111111111111111111111111111111",
                  "sizeFree": 900000
                },
                {
                  "deviceName": "dk3",
                  "name": "Archive",
                  "format": "HFS",
                  "uuid": "22222222222222222222222222222222",
                  "sizeFree": 800000
                }
              ]
            }
          ]
        }
      }
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.map(\.deviceName), ["dk2", "dk3"])
    XCTAssertEqual(records.map(\.name), ["Data", "Archive"])
    XCTAssertFalse(records.contains { $0.deviceName == "wd0" || $0.name == "wd0" })
    XCTAssertTrue(records.allSatisfy(\.builtIn))
  }

  func testBatchRefreshParsesOnlyMaStInventory() {
    let json = """
      {
        "errors": {},
        "settings": {
          "MaSt": {
            "decoded": [
              {
                "deviceName": "wd0",
                "builtin": true,
                "partitions": [
                  {
                    "deviceName": "dk2",
                    "name": "Data",
                    "format": "hfs",
                    "uuid": {"hex": "1343746ea33b5473a8adf43b75e5d004", "length": 16}
                  }
                ]
              },
              {
                "deviceName": "sd0",
                "partitions": [
                  {
                    "deviceName": "dk3",
                    "name": "Untitled 2",
                    "format": "hfs",
                    "uuid": {"hex": "98cd04958940504da7b6e80f87996906", "length": 16}
                  }
                ]
              }
            ]
          },
          "Prof": {
            "decoded": {
              "profiles": [
                {"name": "Default Settings"},
                {"name": "Time Capsule"}
              ],
              "restoreProfile": {
                "name": "restoreProfile"
              }
            }
          }
        }
      }
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.map(\.name), ["Data", "Untitled 2"])
    XCTAssertFalse(records.contains { $0.name == "Default Settings" })
    XCTAssertFalse(records.contains { $0.name == "Time Capsule" })
    XCTAssertFalse(records.contains { $0.name == "restoreProfile" })
  }

  func testOutOfRangeNumericDiskSizesDoNotCrashParser() {
    let json = """
      {
        "decoded": {
          "disks": [
            {
              "deviceName": "wd0",
              "partitions": [
                {
                  "deviceName": "dk2",
                  "name": "Data",
                  "uuid": "11111111111111111111111111111111",
                  "size": 1e40,
                  "sizeFree": 1e40
                }
              ]
            }
          ]
        }
      }
      """

    let records = DiskInventoryParser.parse(stdout: json)

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records.first?.name, "Data")
    XCTAssertNil(records.first?.size)
    XCTAssertNil(records.first?.sizeFree)
  }

  func testMissingExternalArchiveDiskErrorIsPreservedForDisplay() {
    let result = CommandResult(
      arguments: ["host", "--password", "secret", "--archive-disk", "--dry-run"],
      redactedArguments: ["host", "--password", "<password>", "--archive-disk", "--dry-run"],
      stdout: "",
      stderr: "no external AirPort disk partition is available for archive destination\n",
      exitCode: 1
    )

    XCTAssertTrue(result.combinedOutput.contains("no external AirPort disk partition"))
    XCTAssertTrue(result.redactedArguments.contains("<password>"))
  }
}
