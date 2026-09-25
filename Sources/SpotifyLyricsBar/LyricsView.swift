import AppKit
import SwiftUI
import LyricsCore

extension PaletteColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

struct LyricsView: View {
    @ObservedObject var model: PlayerModel
    @State private var showSettings = false
    @State private var showFavorites = false
    @State private var showVersions = false
    @State private var followLyrics = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: AlbumPalette { model.displayPalette }
    private var accent: Color { palette.accent.color }
    private var surface: Color { palette.top.color }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let track = model.track {
                trackCard(track)
                playback(track)
                Divider().overlay(.white.opacity(0.06)).padding(.horizontal, 24)
                if showFavorites { FavoritesView(model: model) } else if showVersions { VersionsView(model: model) } else if showSettings { settings } else { lyricsContent }
            } else {
                if showFavorites { FavoritesView(model: model) } else if showSettings { settings } else { connectionContent }
            }
            if let error = model.commandError {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button { model.commandError = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Fechar aviso")
                }.padding(.horizontal, 24).padding(.bottom, 10)
            }
            footer
        }
        .frame(width: 396, height: 628)
        .background(LinearGradient(colors: [palette.top.color, palette.bottom.color],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: palette)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
            Text("LYRICZ").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2.4)
            Spacer()
            if model.isDemo {
                Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
            } else if model.connection == .connected {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(model.activePlayer?.name ?? "Player").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Menu {
                Toggle("Letra flutuante", isOn: $model.floatingLyrics)
                Button("Trechos favoritos") { showFavorites = true; showVersions = false; showSettings = false }
                Button("Escolher outra versão da letra") {
                    showVersions = true; showFavorites = false; showSettings = false; model.searchVersions()
                }.disabled(model.track == nil)
                Divider()
                Picker("Player", selection: $model.playerPreference) {
                    ForEach(PlayerPreference.allCases) { Text($0.name).tag($0) }
                }
                Button("Abrir Spotify") { model.openPlayer(.spotify) }
                Button("Abrir Apple Music") { model.openPlayer(.appleMusic) }
                Button("Reconectar", action: model.reconnect)
                Button("Buscar letra novamente", action: model.refreshLyrics).disabled(model.track == nil)
                Divider()
                Toggle("Mostrar frase na barra", isOn: $model.showLyricsInBar)
                Divider()
                Button("Sair do Lyricz") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 20)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Mais opções")
        }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
    }

    private func trackCard(_ track: Track) -> some View {
        HStack(spacing: 14) {
            Group {
              if let image = model.albumImage {
                Image(nsImage: image).resizable().scaledToFill()
              } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.38, blue: 0.35), Color(red: 0.17, green: 0.18, blue: 0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
                }
              }
            }
            .frame(width: 66, height: 66).clipShape(RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.system(size: 19, weight: .semibold)).lineLimit(2)
                Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                Text(track.album).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 24)
    }

    private func playback(_ track: Track) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 26) {
                controlButton("backward.end.fill", label: "Faixa anterior") { model.control(.previous) }
                Button { model.control(.playPause) } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(surface).frame(width: 38, height: 38)
                        .background(accent, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(model.isPlaying ? "Pausar" : "Reproduzir")
                controlButton("forward.end.fill", label: "Próxima faixa") { model.control(.next) }
            }.padding(.top, 18)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.09))
                    Capsule().fill(accent.opacity(0.8))
                        .frame(width: geometry.size.width * min(1, max(0, model.position / max(1, track.duration))))
                }
            }.frame(height: 3).accessibilityLabel("Progresso da música")
                .accessibilityValue("\(time(model.position)) de \(time(track.duration))")
            HStack {
                Text(time(model.position))
                Spacer()
                Text(model.isPlaying ? "TOCANDO AGORA" : "EM PAUSA").font(.system(size: 8, weight: .medium)).tracking(1.5)
                Spacer()
                Text(time(track.duration))
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.38))
        }.padding(.horizontal, 24).padding(.bottom, 18)
    }

    @ViewBuilder private var lyricsContent: some View {
        switch model.lyricsState {
        case .idle, .loading:
            VStack(spacing: 14) {
                ProgressView().controlSize(.small).tint(accent)
                Text("Encontrando as palavras…").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            message(icon: "text.magnifyingglass", title: "Ainda sem letra por aqui",
                    detail: "Não encontramos a letra desta versão no LRCLIB.", action: "Tentar novamente", perform: model.refreshLyrics)
        case .failure:
            message(icon: "wifi.exclamationmark", title: "Não foi possível buscar a letra",
                    detail: "Verifique sua conexão e tente novamente em instantes.", action: "Tentar novamente", perform: model.refreshLyrics)
        case .loaded(let lyrics):
            if lyrics.instrumental {
                message(icon: "pianokeys", title: "Só a música", detail: "Esta faixa está marcada como instrumental.")
            } else if lyrics.lines.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LETRA SEM SINCRONIZAÇÃO").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(accent)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(lyrics.plainText.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, stanza in
                                Text(stanza).font(.system(size: 19, weight: .medium)).lineSpacing(9)
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                    .contextMenu {
                                        Button(model.isFavorite(stanza) ? "Remover dos favoritos" : "Favoritar trecho") { model.favorite(stanza) }
                                        Button("Copiar trecho") { copyExcerpt(stanza) }
                                    }
                            }
                        }
                    }
                }.padding(24).frame(maxHeight: .infinity)
            } else {
                syncedLyrics(lyrics)
            }
        }
    }

    private func syncedLyrics(_ lyrics: Lyrics) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("NO RITMO DA MÚSICA").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button { followLyrics.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: followLyrics ? "scope" : "hand.draw")
                        Text(followLyrics ? "Acompanhar" : "Leitura livre")
                    }.font(.system(size: 10)).foregroundStyle(followLyrics ? accent : .white.opacity(0.5))
                }.buttonStyle(.plain).help("Ativar ou desativar a rolagem automática")
            }.padding(.horizontal, 24).padding(.top, 19).padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(lyrics.lines) { line in
                            let active = line.id == model.activeLineID
                            Button { model.seek(to: line) } label: {
                                Text(line.isInstrumental ? "♪  ♪  ♪" : line.text)
                                .font(.system(size: active ? 25 : 22, weight: active ? .semibold : .medium))
                                .foregroundStyle(active ? accent : .white.opacity(line.id < (model.activeLineID ?? -1) ? 0.30 : 0.52))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                                .overlay(alignment: .leading) {
                                    if active { Capsule().fill(accent).frame(width: 3).padding(.vertical, 3) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isSeeking)
                            .help("Ir para \(time(line.playbackPosition(offset: model.lyricOffset, duration: model.track?.duration ?? 0)))")
                            .accessibilityLabel(line.isInstrumental ? "Trecho instrumental" : line.text)
                            .accessibilityHint("Ir para este trecho da música")
                            .contextMenu {
                                if !line.isInstrumental {
                                    Button(model.isFavorite(line.text) ? "Remover dos favoritos" : "Favoritar trecho") { model.favorite(line.text) }
                                    Button("Copiar trecho") { copyExcerpt(line.text) }
                                }
                            }
                            .id(line.id)
                            .accessibilityAddTraits(active ? .isSelected : [])
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 22)
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                             .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onAppear { if let id = model.activeLineID { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: model.activeLineID) { id in
                    guard followLyrics, let id else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: followLyrics) { follow in
                    if follow, let id = model.activeLineID {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }.frame(maxHeight: .infinity)
    }

    @ViewBuilder private var connectionContent: some View {
        switch model.connection {
        case .permissionDenied:
            message(icon: "lock.open", title: "Uma permissão e pronto",
                    detail: "Em Privacidade e Segurança → Automação, permita que o Lyricz controle o \(model.playerName).",
                    action: "Abrir Ajustes do Sistema", perform: model.openAutomationSettings)
            Button("Já permiti · reconectar", action: model.reconnect).buttonStyle(.plain)
                .font(.system(size: 12)).foregroundStyle(accent).padding(.bottom, 35)
        case .playerClosed:
            message(icon: "headphones", title: "Sua próxima música,\ncom todas as palavras.",
                    detail: "Abra o \(model.playerName) neste Mac e dê play.\nA letra acompanha você por aqui.",
                    action: "Abrir \(model.playerPreference.source?.name ?? model.activePlayer?.name ?? "Spotify")", perform: model.openPreferredPlayer)
        case .failure(let error):
            message(icon: "antenna.radiowaves.left.and.right.slash", title: "Vamos reconectar?",
                    detail: error, action: "Tentar novamente", perform: model.reconnect)
        case .connecting:
            message(icon: "waveform", title: "Conectando ao player", detail: "Se o macOS pedir, permita o acesso ao \(model.playerName).")
        default:
            message(icon: "music.note", title: "Dê play em uma música",
                    detail: "A letra aparece assim que uma faixa começar. Anúncios e podcasts não têm letras.",
                    action: "Abrir \(model.playerPreference.source?.name ?? model.activePlayer?.name ?? "Spotify")", perform: model.openPreferredPlayer)
        }
    }

    private var settings: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text("Do seu jeito").font(.system(size: 21, weight: .semibold))
            Picker("Player", selection: $model.playerPreference) {
                ForEach(PlayerPreference.allCases) { Text($0.name).tag($0) }
            }
            Text("No automático, acompanha quem começar a tocar. A escolha manual mantém o player selecionado.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Usar cores da capa", isOn: $model.useAlbumColors).toggleStyle(.switch).tint(accent)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Intensidade das cores"); Spacer(); Text("\(Int(model.colorIntensity * 100))%").monospacedDigit() }
                Slider(value: $model.colorIntensity, in: 0...1, step: 0.05).tint(accent)
                    .accessibilityLabel("Intensidade das cores da capa")
                HStack { Text("Discreto"); Spacer(); Text("Vivo") }.foregroundStyle(.secondary)
            }.disabled(!model.useAlbumColors)
            Toggle("Letra flutuante", isOn: $model.floatingLyrics).toggleStyle(.switch).tint(accent)
            Toggle("Frase atual na barra de menus", isOn: $model.showLyricsInBar).toggleStyle(.switch).tint(accent)
            Toggle("Deslizar frases longas", isOn: $model.scrollLongLines).toggleStyle(.switch).tint(accent)
                .disabled(!model.showLyricsInBar)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Velocidade da letra")
                    Spacer()
                    Text("\(Int(model.scrollSpeed)) pt/s").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $model.scrollSpeed, in: MarqueeMotion.speedRange, step: 1).tint(accent)
                    .accessibilityLabel("Velocidade de deslizamento da letra")
                HStack {
                    Text("Mais lento")
                    Spacer()
                    Text("Mais rápido")
                }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Button("Restaurar velocidade padrão") { model.scrollSpeed = MarqueeMotion.defaultSpeed }
                    .buttonStyle(.plain).foregroundStyle(accent)
            }.disabled(!model.showLyricsInBar || !model.scrollLongLines)
            Toggle("Compactar nos instrumentais", isOn: $model.compactInstrumentals).toggleStyle(.switch).tint(accent)
                .disabled(!model.showLyricsInBar)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Largura na barra")
                    Spacer()
                    Text("\(Int(model.barWidth)) pt").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $model.barWidth, in: 120...420, step: 10).tint(accent)
                    .accessibilityLabel("Largura do texto na barra de menus")
                Text("O tamanho da barra é aplicado ao fechar este painel.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Ajuste de sincronização")
                    Spacer()
                    Text(String(format: "%+.2f s", model.lyricOffset)).foregroundStyle(accent).monospacedDigit()
                }
                Slider(value: $model.lyricOffset, in: -5...5, step: 0.25).tint(accent)
                    .accessibilityLabel("Ajuste de tempo da letra")
                Text("Positivo adianta; negativo atrasa. Salvo automaticamente para esta música, inclusive ao reabrir o app.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                Button("Restaurar sincronização") { model.lyricOffset = 0 }.buttonStyle(.plain).foregroundStyle(accent)
            }.disabled(model.track == nil)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Toggle("Iniciar junto com o Mac", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).tint(accent).disabled(model.isDemo || model.updatingLogin)
                if model.isDemo {
                    Text("Disponível fora da demonstração.").foregroundStyle(.secondary)
                } else if model.loginNeedsApproval {
                    Text("Aguardando liberação em Itens de Início do macOS.").foregroundStyle(.orange)
                    Button("Abrir Itens de Início", action: model.openLoginSettings).buttonStyle(.plain).foregroundStyle(accent)
                } else {
                    Text("O Lyricz aparece na barra de menus ao entrar na sua conta do Mac.").foregroundStyle(.secondary)
                }
                if let error = model.loginError { Text(error).foregroundStyle(.orange) }
            }.font(.system(size: 11))
          }.font(.system(size: 12)).padding(24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { model.refreshLoginStatus() }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: model.lyrics?.lines.isEmpty == false ? "checkmark.circle.fill" : "text.quote")
                    .foregroundStyle(model.lyrics?.lines.isEmpty == false ? accent.opacity(0.7) : .white.opacity(0.4))
                Text(model.lyrics?.lines.isEmpty == false ? "Sincronizado" : "Letras por")
                Text("·").foregroundStyle(.white.opacity(0.2))
                Link("LRCLIB", destination: URL(string: "https://lrclib.net")!).foregroundStyle(.white.opacity(0.6))
            }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            if case .words(let text) = model.lyricMoment {
                Button { model.favorite(text) } label: {
                    Image(systemName: model.isFavorite(text) ? "heart.fill" : "heart")
                        .foregroundStyle(accent).frame(width: 25, height: 26)
                }.buttonStyle(.plain).help("Favoritar frase atual").accessibilityLabel("Favoritar frase atual")
            }
            Button {
                if showFavorites || showVersions { showFavorites = false; showVersions = false; showSettings = false }
                else { showSettings.toggle() }
            } label: {
                Image(systemName: (showSettings || showFavorites || showVersions) ? "text.alignleft" : "slider.horizontal.3")
                    .font(.system(size: 13)).foregroundStyle(showSettings ? accent : .white.opacity(0.6))
                    .frame(width: 28, height: 26)
            }.buttonStyle(.plain).accessibilityLabel((showSettings || showFavorites || showVersions) ? "Voltar à letra" : "Ajustes")
        }.padding(.horizontal, 24).padding(.vertical, 13)
            .background(.black.opacity(0.14))
    }

    private func message(icon: String, title: String, detail: String,
                         action: String? = nil, perform: (() -> Void)? = nil) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(accent)
                .frame(width: 80, height: 80).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.system(size: 21, weight: .semibold)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button(action, action: perform).buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(surface).padding(.horizontal, 18).padding(.vertical, 10)
                    .background(accent, in: Capsule()).padding(.top, 4)
            }
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controlButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65)).frame(width: 28, height: 28)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
