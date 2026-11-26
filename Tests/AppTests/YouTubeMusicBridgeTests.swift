import AppKit
import JavaScriptCore
import XCTest
import LyricsCore
@testable import SpotifyLyricsBar

final class YouTubeMusicBridgeTests: XCTestCase {
    func testMetadataAndPlaybackAreDecodedWithStableYouTubeIdentity() throws {
        let snapshot = try XCTUnwrap(YouTubeMusicBridge.decode("""
        {"id":"abc_123-xyz","title":"All We Know","artist":"Paramore","album":"All We Know Is Falling",
        "duration":193.5,"position":25.2,"playing":true,"artwork":"https://i.ytimg.com/vi/abc/default.jpg"}
        """))
        XCTAssertEqual(snapshot.track.id, "youtubeMusic:abc_123-xyz")
        XCTAssertEqual(snapshot.track.artist, "Paramore")
        XCTAssertEqual(snapshot.track.duration, 193.5)
        XCTAssertEqual(snapshot.position(at: snapshot.sampledAt), 25.2)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertNotNil(snapshot.track.artworkURL)
        XCTAssertNil(try YouTubeMusicBridge.decode("null"))
        XCTAssertNil(try YouTubeMusicBridge.decode("""
        {"id":"123","title":"Live","artist":"Artist","album":"","duration":0,"position":0,"playing":true}
        """))
    }

    func testBrowserScriptsCompileAgainstInstalledDictionaries() throws {
        for browser in YouTubeMusicBridge.browsers where NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) != nil {
            let script = try XCTUnwrap(NSAppleScript(source: YouTubeMusicBridge.discoveryScript(browser)))
            var error: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&error), "\(browser.name): \(String(describing: error))")
        }
    }

    func testPageReaderRejectsOtherOriginsAndAdsAndReadsPausedTracks() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var location = { origin: 'https://music.youtube.com', href: 'https://music.youtube.com/watch?v=abc' };
        var ad = false;
        var video = { duration: 180, currentTime: 40, paused: true, ended: false, readyState: 4, closest: () => player };
        var navigator = { mediaSession: { metadata: { title: 'Song', artist: 'Artist', album: 'Album', artwork: [{src:'https://i.ytimg.com/art.jpg'}] } } };
        var player = { querySelector: () => null, getVideoData: () => ({ video_id: 'abc' }), classList: { contains: () => ad } };
        var document = { querySelectorAll: () => [video], querySelector: (q) => q === '#movie_player' ? player : null };
        """)
        let json = try XCTUnwrap(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString())
        XCTAssertNil(js.exception)
        let snapshot = try XCTUnwrap(YouTubeMusicBridge.decode(json))
        XCTAssertEqual(snapshot.track.title, "Song")
        XCTAssertFalse(snapshot.isPlaying)
        // The current miniplayer exposes the video ID on its title link rather
        // than a page-world getVideoData method (including on playlist URLs).
        js.evaluateScript("player.getVideoData = undefined; player.querySelector = () => ({href:'https://music.youtube.com/watch?v=new_ID-123'});")
        let currentLayout = try XCTUnwrap(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString())
        XCTAssertNil(js.exception)
        XCTAssertEqual(try YouTubeMusicBridge.decode(currentLayout)?.track.id, "youtubeMusic:new_ID-123")
        js.evaluateScript("ad = true")
        XCTAssertEqual(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString(), "null")
        js.evaluateScript("ad = false; location.origin = 'https://music.youtube.com.evil.example'")
        XCTAssertEqual(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString(), "null")
    }

    func testAutomaticQueueChangeDoesNotMixOldMediaWithNewMetadata() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var location = {origin:'https://music.youtube.com', href:'https://music.youtube.com/watch?v=previous'};
        var navigator = {mediaSession:{metadata:{title:'Previous song',artist:'Artist',album:'Album'}}};
        function item(id, title, duration, position, paused, ended) {
            const player = {classList:{contains:()=>false}, querySelector:()=>({href:'https://music.youtube.com/watch?v='+id, textContent:title})};
            return {duration, currentTime:position, paused, ended, readyState:4, closest:()=>player};
        }
        var oldVideo = item('previous','Previous song',249,209,false,false);
        var videos = [oldVideo];
        var document = {querySelector:()=>null, querySelectorAll:()=>videos};
        """)
        func read() throws -> PlaybackSnapshot? {
            let value = try XCTUnwrap(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString())
            XCTAssertNil(js.exception)
            return try YouTubeMusicBridge.decode(value)
        }
        XCTAssertEqual(try read()?.track.duration, 249)
        // Autoplay updates Media Session first. Reject a partial transition.
        js.evaluateScript("navigator.mediaSession.metadata.title='Love Me Different'")
        XCTAssertNil(try read())
        // The old video stays first, and the URL still points to its song.
        js.evaluateScript("videos.push(item('current','Love Me Different',213,0,false,false))")
        let next = try XCTUnwrap(read())
        XCTAssertEqual(next.track.id, "youtubeMusic:current")
        XCTAssertEqual(next.track.title, "Love Me Different")
        XCTAssertEqual(next.track.duration, 213)
        XCTAssertEqual(next.position(at: next.sampledAt), 0)
        XCTAssertEqual(URLComponents(url: LyricsClient.request(for: next.track).url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "duration" }?.value, "213")
        // Pausing the new song must not resurrect the previous media element.
        js.evaluateScript("videos[1].paused=true; videos[1].currentTime=12")
        let paused = try XCTUnwrap(read())
        XCTAssertEqual(paused.track.id, "youtubeMusic:current")
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.position(at: paused.sampledAt), 12)
        // A stale address-bar URL is never used as a song ID.
        js.evaluateScript("videos=[item('', 'Love Me Different',213,12,true,false)]")
        XCTAssertNil(try read())
    }

    func testGaplessTimelineUsesSongProgressInsteadOfCumulativeMediaTime() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var location = {origin:'https://music.youtube.com'};
        var title="Good Ol' Days", id='previous';
        var navigator={mediaSession:{metadata:{title,artist:'Hayley Williams',album:'Album'}}};
        var slider={max:'204',value:'195'};
        var player={classList:{contains:()=>false},querySelector:()=>({textContent:title,href:'https://music.youtube.com/watch?v='+id})};
        var video={duration:230,currentTime:195,paused:false,ended:false,readyState:4,closest:()=>player};
        var document={querySelectorAll:()=>[video],querySelector:q=>q.includes('MiniPlayerProgressBar')?slider:null};
        """)
        func read() throws -> PlaybackSnapshot {
            let value = try XCTUnwrap(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString())
            XCTAssertNil(js.exception)
            return try XCTUnwrap(YouTubeMusicBridge.decode(value))
        }
        XCTAssertEqual(try read().track.duration, 204, "Prefetching the next song must not extend this song")
        // Real autoplay behavior: same video and source, no reset of currentTime.
        js.evaluateScript("title='Showbiz';id='next';navigator.mediaSession.metadata.title=title;slider.max='230';slider.value='0';video.duration=253.6;video.currentTime=204;")
        let next = try read()
        XCTAssertEqual(next.track.id, "youtubeMusic:next")
        XCTAssertEqual(next.track.duration, 230)
        XCTAssertEqual(next.position(at: next.sampledAt), 0)
        js.evaluateScript("video.duration=303.5;video.currentTime=220;slider.value='16';")
        let advancing = try read()
        XCTAssertEqual(advancing.track.duration, 230)
        XCTAssertEqual(advancing.position(at: advancing.sampledAt), 16)
        js.evaluateScript(YouTubeMusicBridge.mediaJavaScript)
        XCTAssertEqual(js.evaluateScript("readCurrentMedia().offset + 25")?.toDouble(), 229,
                       "Seeking to 25s in the song must address 229s in the stitched media")
        js.evaluateScript("""
        var Event=function(type){this.type=type};
        slider.tagName='INPUT';
        slider.dispatchEvent=event=>{if(event.type==='change') video.currentTime=204+Number(slider.value)};
        var current=readCurrentMedia();
        """)
        js.evaluateScript(YouTubeMusicBridge.seekJavaScript(position: 25))
        XCTAssertNil(js.exception)
        XCTAssertEqual(js.evaluateScript("video.currentTime")?.toDouble(), 229)
        let sought = try read()
        XCTAssertEqual(sought.position(at: sought.sampledAt), 25)
        js.evaluateScript("slider.max='0'")
        XCTAssertEqual(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString(), "null")
    }

    func testYouTubeParticipatesInAutomaticSelectionAndManualPreferencePersists() async {
        let track = Track(id: "youtubeMusic:abc", title: "Song", artist: "Artist", album: "", duration: 100)
        let reading = PlaybackSnapshot(track: track, isPlaying: true, position: 0)
        XCTAssertEqual(PlayerSelection.choose(readings: [.youtubeMusic: reading], current: .spotify,
                                              previouslyPlaying: []), .youtubeMusic)
        await MainActor.run {
            let name = "LyriczYouTubeTests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let model = PlayerModel(demo: true, defaults: defaults)
            model.playerPreference = .youtubeMusic
            XCTAssertEqual(PlayerModel(demo: true, defaults: defaults).playerPreference, .youtubeMusic)
        }
    }
}
