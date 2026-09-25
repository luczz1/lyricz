import AppKit
import SwiftUI
import LyricsCore

@MainActor func copyExcerpt(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct FavoritesView: View {
    @ObservedObject var model: PlayerModel
    @State private var notice: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Trechos favoritos")).font(.title2.bold())
                if model.favorites.isEmpty {
                    Text(L("Toque no coração da frase atual ou clique com o botão direito em um verso para salvar."))
                        .foregroundStyle(.secondary)
                }
                if let notice { Text(notice).font(.caption).foregroundStyle(model.displayPalette.accent.color) }
                ForEach(model.favorites) { favorite in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if let data = favorite.artwork, let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading) {
                                Text(favorite.title).font(.headline)
                                Text(favorite.artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(favorite.text).font(.system(size: 17, weight: .medium)).textSelection(.enabled)
                        HStack {
                            Button(L("Copiar")) { copyExcerpt("\(favorite.text)\n— \(favorite.title) · \(favorite.artist)"); notice = L("Trecho copiado.") }
                            Button(L("Salvar imagem")) { export(favorite) }
                            Spacer()
                            Button { model.removeFavorite(favorite.id) } label: { Image(systemName: "heart.slash") }
                                .help(L("Remover dos favoritos")).accessibilityLabel(L("Remover dos favoritos"))
                        }.font(.caption).buttonStyle(.borderless)
                    }.padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor private func export(_ favorite: FavoriteExcerpt) {
        let renderer = ImageRenderer(content: ExcerptCard(excerpt: favorite))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            notice = L("Não foi possível criar a imagem."); return
        }
        guard let delegate = NSApp.delegate as? AppDelegate else {
            notice = L("Não foi possível abrir a janela para salvar."); return
        }
        delegate.saveExcerptImage(data, title: favorite.title) { message in
            notice = message
        }
    }
}

struct ExcerptCard: View {
    let excerpt: FavoriteExcerpt
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("LYRICZ").font(.system(size: 14, weight: .bold)).tracking(4).foregroundStyle(.white.opacity(0.55))
            Text("“\(excerpt.text)”").font(.system(size: 34, weight: .semibold)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if let data = excerpt.artwork, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(excerpt.title).font(.system(size: 19, weight: .semibold))
                    Text(excerpt.artist).font(.system(size: 16)).foregroundStyle(.white.opacity(0.65))
                }
            }
        }.padding(44).frame(width: 540, alignment: .leading)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.26), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct VersionsView: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Versões da letra")).font(.title2.bold())
                Text(L("Compare o álbum, a duração e o trecho antes de escolher. A escolha fica salva para esta música."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Usar escolha automática")) { model.selectVersion(nil) }
                    .disabled(model.selectedVersionID == nil)
                if model.searchingVersions { ProgressView(L("Buscando versões…")) }
                else if let error = model.versionsError {
                    Text(error).foregroundStyle(.orange)
                    Button(L("Tentar novamente"), action: model.searchVersions)
                } else if model.versions.isEmpty {
                    Text(L("Nenhuma alternativa encontrada.")).foregroundStyle(.secondary)
                    Button(L("Buscar versões"), action: model.searchVersions)
                }
                ForEach(model.versions) { version in
                    Button { model.selectVersion(version) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(version.albumName.isEmpty ? version.trackName : version.albumName).font(.headline)
                                Spacer()
                                if model.selectedVersionID == version.id { Image(systemName: "checkmark.circle.fill") }
                            }
                            Text("\(Int(version.duration) / 60):\(String(format: "%02d", Int(version.duration) % 60)) · \(L(version.instrumental ? "Instrumental" : version.lyrics.lines.isEmpty ? "Sem sincronização" : "Sincronizada"))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(version.trackName) · \(version.artistName)").font(.caption).foregroundStyle(.secondary)
                            Text(String(version.lyrics.plainText.prefix(180))).font(.caption).lineLimit(3).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(.white.opacity(model.selectedVersionID == version.id ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.padding(24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.track?.id) { _ in model.searchVersions() }
    }
}

struct FloatingLyricsView: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.track.map { "\($0.title) · \($0.artist)" } ?? "Lyricz").font(.caption).lineLimit(1)
                Spacer()
                Button { model.floatingLyrics = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L("Fechar letra flutuante"))
            }.foregroundStyle(.white.opacity(0.65))
            Text(model.barTitle).font(.system(size: 24, weight: .semibold)).lineLimit(4).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .foregroundStyle(model.displayPalette.accent.color)
            HStack {
                Button { model.control(.playPause) } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(L(model.isPlaying ? "Pausar" : "Reproduzir"))
                Spacer()
                if case .words(let text) = model.lyricMoment {
                    Button { model.favorite(text) } label: { Image(systemName: model.isFavorite(text) ? "heart.fill" : "heart") }
                        .accessibilityLabel(L("Favoritar frase atual"))
                }
            }.buttonStyle(.plain).foregroundStyle(model.displayPalette.accent.color)
        }.padding(20).frame(minWidth: 280, minHeight: 150)
            .background(LinearGradient(colors: [model.displayPalette.top.color, model.displayPalette.bottom.color], startPoint: .topLeading, endPoint: .bottomTrailing))
            .preferredColorScheme(.dark)
    }
}
