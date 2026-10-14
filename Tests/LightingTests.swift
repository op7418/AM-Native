import Foundation
@main struct LightingTests {
 static func main() throws {
  let original=LightState(settings:[0,0,1],pattern:[1,36,0,16]+Array(repeating:255,count:36))
  try original.validate(.mouse)
  for mode in 0...2 {
   for speed in [1,7,10] {
    for count in [1,2,7] {
     let colors=Array(repeating:[UInt8(64),128,255],count:count)
     let p=try LightState.pattern(mode:mode,speed:speed,colors:colors)
     try LightState(settings:[1,UInt8(mode),UInt8(speed)],pattern:p).validate(.mouse)
     precondition(word(p,1)==p.count-4 && p.count<=1000)
     let nv:[UInt8]=[0]+littleEndian(25088)+littleEndian(p.count)+p
     let decodedNV = try LightState.nv(nv,id:25088); precondition(decodedNV==p)
    }
   }
  }
  for mode in 0...2 {
   for speed in 1...10 {
    let p=try LightState.pattern(mode:mode,speed:speed,colors:[[64,128,255],[255,96,32]],maximumBytes:128)
    try LightState(settings:[1,UInt8(mode),UInt8(speed)],pattern:p).validate(.mouse)
    precondition(p.count<=128)
   }
  }
  do { _=try LightState.pattern(mode:1,speed:1,colors:Array(repeating:[64,128,255],count:7),maximumBytes:128);fatalError("Unsupported RF pattern accepted") } catch {}
  let large:[UInt8] = [1] + littleEndian(5250) + [16] + Array(repeating:UInt8(128),count:5250)
  precondition(large.count>4096)
  let payload:[UInt8]=[0]+littleEndian(25088)+littleEndian(large.count)+large
  let frame:[UInt8]=[5,0x5b]+littleEndian(payload.count+2)+littleEndian(0x0a0c)+payload
  var decoder=RaceDecoder();var decoded:[RaceFrame]=[]
  for i in stride(from:0,to:frame.count,by:53) { decoded += decoder.append(bytes:Array(frame[i..<min(i+53,frame.count)])) }
  precondition(decoded.count==1 && decoded[0].payload==payload)
  for invalid in [[UInt8](),[0,0,98,40,0,1,0],[0,10,96,3,0,0,0,1]] {
   do { _=try LightState.nv(invalid,id:25088);fatalError("incomplete or wrong NV accepted") } catch {}
  }
  let headerLength=try LightState.patternLength(header:[1,112,2,16])
  precondition(headerLength == 628)
  for header:[UInt8] in [[],[1,0,0,16],[2,36,0,16],[1,35,0,16],[1,36,0,0],[1,255,255,16]] {
   do { _=try LightState.patternLength(header:header);fatalError("invalid header accepted") } catch {}
  }
  let before=LightSnapshot(target:.mouse,identity:1,profile:0,state:original)
  let changed=LightState(settings:[1,1,7],pattern:try LightState.pattern(mode:1,speed:7,colors:[[64,128,255]]))
  let after=before.replacing(changed)
  precondition(LightingService.canRestore(before,before:before,after:after))
  precondition(LightingService.canRestore(before.replacing(LightState(settings:original.settings,pattern:changed.pattern)),before:before,after:after))
  precondition(!LightingService.canRestore(LightSnapshot(target:.mouse,identity:2,profile:0,state:changed),before:before,after:after))
  precondition(!LightingService.canRestore(LightSnapshot(target:.mouse,identity:1,profile:1,state:changed),before:before,after:after))
  precondition(!LightingService.canRestore(before.replacing(LightState(settings:[1,2,9],pattern:changed.pattern)),before:before,after:after))
  let roundTrip=try JSONDecoder().decode(LightReceipt.self,from:JSONEncoder().encode(LightReceipt(before:before,after:after)))
  precondition(roundTrip.before==before && roundTrip.after==after)
  try LightState(settings:[0,5,0,1,100,0,1,100,0,1,100,92,201],pattern:[]).validate(.receiver)
  print("PASS: lighting NV completeness, exact raw backups, 3 modes / 7 colors / speed boundaries, long fragmented frames, partial-write recovery, stale device/profile rejection")
 }
}
