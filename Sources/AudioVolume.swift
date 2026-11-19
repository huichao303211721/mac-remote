import AudioToolbox
import CoreAudio

enum AudioVolume {
    private static func device() -> AudioDeviceID {
        var d = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &d)
        return d
    }

    private static func read(_ dev: AudioDeviceID) -> Float {
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &addr), AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr {
            return vol
        }
        // 回退到左右声道
        var avg: Float = 0, cnt = 0
        for ch in [UInt32(1), UInt32(2)] {
            var v: Float32 = 0
            var sz = UInt32(MemoryLayout<Float32>.size)
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput,
                                               mElement: ch)
            if AudioObjectHasProperty(dev, &a), AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &v) == noErr {
                avg += v; cnt += 1
            }
        }
        return cnt > 0 ? avg / Float(cnt) : 0
    }

    private static func write(_ dev: AudioDeviceID, _ value: Float) {
        var v = Float32(max(0, min(1, value)))
        let size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &addr), AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &v) == noErr {
            return
        }
        for ch in [UInt32(1), UInt32(2)] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput,
                                               mElement: ch)
            if AudioObjectHasProperty(dev, &a) {
                AudioObjectSetPropertyData(dev, &a, 0, nil, size, &v)
            }
        }
    }

    static func step(_ dir: Int) {
        let dev = device()
        guard dev != 0 else { return }
        var vol = read(dev)
        if vol < 0.005 { vol = 0 }
        vol += Float(dir) * 0.0625
        if vol < 0.02 && dir < 0 { vol = 0 }   // 最小档直接静音
        write(dev, vol)
        Log.line("volume -> \(Int(vol * 100))%")
    }

    static func toggleMute() {
        let dev = device()
        guard dev != 0 else { return }
        let cur = read(dev)
        if cur > 0.001 {
            UserDefaults.standard.set(cur, forKey: "lastVolume")
            write(dev, 0)
            Log.line("mute on")
        } else {
            let last = UserDefaults.standard.float(forKey: "lastVolume")
            write(dev, last > 0 ? last : 0.4)
            Log.line("mute off")
        }
    }
}
