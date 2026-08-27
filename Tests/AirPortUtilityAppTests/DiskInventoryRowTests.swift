import XCTest

@testable import AirPortUtilityCore

/// The two small lines under a volume name in the Disks pane.
///
/// Numbers are formatted through `ByteCountFormatter`, which follows the
/// machine's locale rather than the app language, so these build their
/// expectations the same way instead of hard-coding "1 TB" / "1 To".
final class DiskInventoryRowTests: XCTestCase {

  private let megabyte: Int64 = 1024 * 1024

  private func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }

  private func record(
    size: Int64? = nil, sizeFree: Int64? = nil, sizeUsed: Int64? = nil,
    vendor: String = "", revision: String = "", smartStatus: String = ""
  ) -> DiskRecord {
    DiskRecord(
      deviceName: "dk2", name: "Data2000", format: "hfs", uuid: "uuid-1",
      size: size, sizeFree: sizeFree, builtIn: true, vendor: vendor,
      revision: revision, sizeUsed: sizeUsed, smartStatus: smartStatus)
  }

  /// The point of the line: "1.34 TB / 2 TB" never says which number is which.
  func testCapacityLineSaysWhichNumberIsTheUsedOne() throws {
    let used = 500 * megabyte
    let total = 1000 * megabyte
    let line = try XCTUnwrap(
      DiskInventoryRow.capacityLine(for: record(size: total, sizeUsed: used)))

    let usedRange = try XCTUnwrap(line.range(of: byteCount(used)))
    let totalRange = try XCTUnwrap(line.range(of: byteCount(total)))
    XCTAssertTrue(usedRange.upperBound <= totalRange.lowerBound, "used comes first: \(line)")

    let between = line[usedRange.upperBound..<totalRange.lowerBound]
    XCTAssertTrue(
      between.contains(where: \.isLetter),
      "nothing labels the first number in \"\(line)\"")
  }

  /// Partitions report `sizeUsed`, but not every device does; the pane must not
  /// fall back to an unlabelled pair when it has to derive the value.
  func testCapacityLineDerivesUsedFromFreeWhenTheDeviceOmitsIt() throws {
    let total = 1000 * megabyte
    let line = try XCTUnwrap(
      DiskInventoryRow.capacityLine(for: record(size: total, sizeFree: 400 * megabyte)))

    XCTAssertTrue(line.contains(byteCount(600 * megabyte)), line)
    XCTAssertTrue(line.contains(byteCount(total)), line)
  }

  func testCapacityLineAppendsTheSMARTStatusAndOmitsItWhenUnreported() throws {
    let withStatus = try XCTUnwrap(
      DiskInventoryRow.capacityLine(
        for: record(size: megabyte, sizeUsed: 0, smartStatus: "verified")))
    XCTAssertTrue(withStatus.contains("SMART"), withStatus)
    XCTAssertTrue(withStatus.contains(localized("verified")), withStatus)

    let withoutStatus = try XCTUnwrap(
      DiskInventoryRow.capacityLine(for: record(size: megabyte, sizeUsed: 0)))
    XCTAssertFalse(withoutStatus.contains("SMART"), withoutStatus)
  }

  /// A device that reports neither capacity nor health has no second line at
  /// all, rather than an empty one taking up row height.
  func testDetailLinesAreAbsentWhenNothingIsReported() {
    XCTAssertNil(DiskInventoryRow.capacityLine(for: record()))
    XCTAssertNil(DiskInventoryRow.hardwareLine(for: record()))
  }

  func testHardwareLineJoinsVendorAndRevisionAndSkipsMissingHalves() throws {
    let both = try XCTUnwrap(
      DiskInventoryRow.hardwareLine(
        for: record(vendor: "WDC WD20EARX-00PASB0", revision: "51.0AB51")))
    XCTAssertEqual(both, "WDC WD20EARX-00PASB0 · 51.0AB51")

    let vendorOnly = try XCTUnwrap(
      DiskInventoryRow.hardwareLine(for: record(vendor: "WDC WD20EARX-00PASB0", revision: "  ")))
    XCTAssertEqual(vendorOnly, "WDC WD20EARX-00PASB0")
  }
}
