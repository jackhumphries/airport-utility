import XCTest

@testable import AirPortUtilityCore

final class DiskInventoryParserTests: XCTestCase {

  /// The shape a real Time Capsule actually returns for MaSt: a bare array, and
  /// every integer wrapped as {"type": "integer", "decimal": "...", "width": n}
  /// rather than sent as a JSON number. Decoding only bare numbers and strings
  /// silently produced nil sizes, so the pane showed no free space at all.
  /// Identifiers here are anonymised; the structure is verbatim.
  func testParsesTheWrappedIntegerFormARealDeviceSends() {
    let json = """
      [{
        "blockSize": {"decimal": "512", "type": "integer", "width": 2},
        "builtin": true,
        "deviceName": "wd0",
        "info": "Disk 1",
        "partitions": [{
          "deviceName": "dk2",
          "format": "hfs",
          "name": "Data2000",
          "size": {"decimal": "1905681", "type": "integer", "width": 4},
          "sizeFree": {"decimal": "623863", "type": "integer", "width": 4},
          "sizeUsed": {"decimal": "1281818", "type": "integer", "width": 4},
          "uuid": {"hex": "00000000000000000000000000000001", "length": 16, "type": "bytes"}
        }],
        "size": {"decimal": "1907729", "type": "integer", "width": 4},
        "smartStatus": "verified",
        "uuid": {"hex": "00000000000000000000000000000002", "length": 16, "type": "bytes"}
      }]
      """
    let records = DiskInventoryParser.parse(stdout: json)
    XCTAssertEqual(records.count, 1)
    let record = records[0]
    XCTAssertEqual(record.name, "Data2000")
    XCTAssertEqual(record.sizeFree, 623_863 * 1024 * 1024)
    XCTAssertEqual(record.size, 1_905_681 * 1024 * 1024)
    XCTAssertEqual(record.smartStatus, "verified")
    XCTAssertTrue(record.builtIn)
  }

  /// Some devices report capacity on the physical disk rather than on each
  /// partition. A partition with no size of its own falls back to the disk's,
  /// so the pane shows free space instead of nothing.
  func testPartitionInheritsCapacityFromItsDisk() {
    let json = """
      {"decoded": {"disks": [{"deviceName": "wd0", "size": 1000, "sizeFree": 400,
        "partitions": [
          {"deviceName": "dk2", "name": {"type":"bytes","text":"Data"},
           "uuid": {"type":"bytes","hex":"aa"}}
        ]}]}}
      """
    let record = DiskInventoryParser.parse(stdout: json).first
    XCTAssertEqual(record?.sizeFree, 400 * 1024 * 1024)
    XCTAssertEqual(record?.size, 1000 * 1024 * 1024)
  }

  /// A partition that reports its own capacity keeps it.
  func testPartitionCapacityWinsOverTheDisk() {
    let json = """
      {"decoded": {"disks": [{"deviceName": "wd0", "size": 1000, "sizeFree": 400,
        "partitions": [
          {"deviceName": "dk2", "name": {"type":"bytes","text":"Data"},
           "uuid": {"type":"bytes","hex":"aa"}, "size": 500, "sizeFree": 250}
        ]}]}}
      """
    XCTAssertEqual(
      DiskInventoryParser.parse(stdout: json).first?.sizeFree, 250 * 1024 * 1024)
  }

  /// The device reports SMART once per physical disk, so every partition on that
  /// disk must inherit it -- otherwise the pane shows a health status for one
  /// volume and nothing for its sibling.
  func testSMARTStatusIsCarriedFromTheDiskToItsPartitions() {
    let json = """
      {"decoded": {"disks": [{"deviceName": "wd0", "builtIn": true,
        "smartStatus": "Verified",
        "partitions": [
          {"deviceName": "dk2", "name": {"type":"bytes","text":"Data"}, "uuid": {"type":"bytes","hex":"aa"}},
          {"deviceName": "dk3", "name": {"type":"bytes","text":"Backup"}, "uuid": {"type":"bytes","hex":"bb"}}
        ]}]}}
      """
    let records = DiskInventoryParser.parse(stdout: json)
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records.map(\.smartStatus), ["Verified", "Verified"])
  }

  /// A partition that reports its own status keeps it.
  func testPartitionSMARTStatusWinsOverTheDisk() {
    let json = """
      {"decoded": {"disks": [{"deviceName": "wd0", "smartStatus": "Verified",
        "partitions": [
          {"deviceName": "dk2", "name": {"type":"bytes","text":"Data"},
           "uuid": {"type":"bytes","hex":"aa"}, "smartStatus": "Failing"}
        ]}]}}
      """
    XCTAssertEqual(DiskInventoryParser.parse(stdout: json).first?.smartStatus, "Failing")
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

  func testMockInventoryCarriesDriveDetail() {
    let records = DiskInventoryParser.parse(stdout: AirportMockBackend.maStJSON)
    let first = records.first
    XCTAssertEqual(first?.vendor, "WDC WD20EARX-00PASB0")
    XCTAssertEqual(first?.revision, "51.0AB51")
    XCTAssertEqual(first?.smartStatus, "verified")
    XCTAssertNotNil(first?.sizeUsed)
  }
}
