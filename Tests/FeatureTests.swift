import Foundation
@main struct FeatureTests {
 static func main() throws {
  precondition(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.9")!)
  precondition(ReleaseVersion("V1.8.4") == ReleaseVersion("1.8.4"))
  for invalid in ["", "latest", "1.2", "1..2", "-1.2.3", "1.2.3 extra"] { precondition(ReleaseVersion(invalid) == nil) }
  let manifest = Data(#"{"data":[{"version":"V1.9.0","description":"old"},{"version":"V1.10.0","description":"new"},{"version":"bad"}]}"#.utf8)
  let driver = try OfficialUpdateService.parseDriver(manifest)
  precondition(driver.version == "V1.10.0")
  for id in 1...7 {
   let type = MouseControl(rawValue:id)!.defaultType
   let mapping = try KeyMapping.parse([0,UInt8(id),type], expectedID:id)
   precondition(mapping.type == type && mapping.params.isEmpty)
  }
  do { _ = try KeyMapping.parse([0,4,6,0], expectedID:4); fatalError("truncated shortcut accepted") } catch {}
  do { _ = try KeyMapping.parse([0,3,3], expectedID:4); fatalError("wrong physical key accepted") } catch {}
  let copy = MappingAction.all.first{$0.id == "copy"}!.mapping(for:.back)
  precondition(copy.type == 6 && copy.params == [0,0,6,8])
  let custom = try KeyMapping.parse([0,5,8,1,2,3,4], expectedID:5)
  let restored = try JSONDecoder().decode(KeyMapping.self,from:JSONEncoder().encode(custom))
  precondition(restored == custom)
  let baseline = MappingSnapshot(identity: 1, profile: 0, mappings: MouseControl.allCases.map { KeyMapping(keyID: $0.rawValue, type: $0.defaultType, params: []) })
  var frontDraft = MappingDraft(control: .forward, baseline: baseline)
  precondition(frontDraft.actionID == "forward" && frontDraft.proposed?.keyID == 4)
  frontDraft.actionID = "copy"
  let captured = frontDraft.proposed!
  let backDraft = MappingDraft(control: .back, baseline: baseline)
  precondition(backDraft.actionID == "back" && backDraft.proposed?.keyID == 5)
  precondition(captured.keyID == 4 && captured.params == [0,0,6,8])
  let unknownDraft = MappingDraft(control: .back, baseline: baseline.replacing(custom))
  precondition(unknownDraft.actionID == nil && unknownDraft.proposed == nil && unknownDraft.current == custom)
  print("PASS: per-control draft isolation, front/back action selection, immutable save target, unknown mapping preservation")
  print("PASS: numeric release ordering, invalid version rejection, driver manifest, seven real key fixtures, shortcut encoding, unknown mapping preservation")
 }
}
