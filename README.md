# Guitar2 🎸

**Leitor de partituras e tablaturas com suporte a Guitar Pro**

## Funcionalidades

- 📄 **Abertura de arquivos**: GP3, GP4, GP5, GPX, GP
- 🎼 **Partitura e Tablatura**: Renderizadas via alphaTab (nativo Android) com transporte (play/pause)
- 🔊 **Áudio**: Reprodução via SoundFont usando alphaTab AlphaSynth
- 🎯 **Modo Prática**: Prática progressiva com controle de BPM, repetições e aceleração integrado à tela de partitura
- 📊 **Histórico**: Gráfico de evolução do BPM ao longo das sessões
- 🖨️ **Impressão**: Exporta todas as páginas da faixa selecionada como PDF
- 🎨 **Waveform**: Visualizador de áudio que reage ao som em tempo real (layout horizontal)
- 🌳 **Navegador de arquivos**: Scan recursivo de pastas com filtro GP, favoritos e busca

## Formatos Suportados

| Extensão | Formato | Engine |
|----------|---------|--------|
| `.gp3`, `.gp4`, `.gp5` | Guitar Pro 3/4/5 | alphaTab |
| `.gpx`, `.gp` | Guitar Pro 6+ | alphaTab |

## Arquitetura

```
lib/
├── main.dart                  # Entry point, MaterialApp, rotas
├── models/
│   ├── music_note.dart        # MusicNote, Measure, ScoreData
│   ├── file_entry.dart        # FileEntry (navegador de arquivos)
│   └── practice_session.dart  # PracticeSession (histórico Hive)
├── services/
│   ├── music_parser_service.dart  # Parser GP via alphaTab
│   ├── practice_service.dart      # Controle de velocidade de prática
│   ├── file_scanner_service.dart  # Scan de diretório (GP only)
│   └── settings_service.dart      # Preferências Hive
├── viewmodels/                # Riverpod StateNotifier
│   ├── practice_viewmodel.dart
│   └── file_tree_viewmodel.dart
├── views/                     # Telas
│   ├── file_tree_screen.dart
│   ├── score_screen.dart      # Tela principal com partitura
│   ├── history_screen.dart
│   └── export_config_screen.dart
├── widgets/                   # Componentes reutilizáveis
│   ├── alpha_tab_view.dart    # PlatformView Android (alphaTab)
│   ├── waveform_visualizer.dart  # Visualizador de áudio em tempo real
│   ├── practice_mode_overlay.dart  # Modo prática como bottom sheet
│   ├── effects_sheet.dart     # Controles de efeitos de áudio
│   ├── file_tree_widget.dart
│   └── bpm_chart_widget.dart
└── painters/                  # Canvas painters (export)
    ├── score_painter.dart
    ├── tab_painter.dart
    └── chord_painter.dart

android/app/src/main/kotlin/.../
├── MainActivity.kt            # Entry point Android
├── AlphaTabViewFactory.kt     # PlatformView + alphaTab API
├── AudioEffectsHandler.kt     # Equalizer, Reverb, BassBoost
└── AudioVisualizerHandler.kt  # Visualizer API para waveform
```

## Estado do Projeto

### ✅ Implementado
- Navegador de arquivos com scan recursivo (apenas GP) e cache Hive
- Renderização de partitura/tablatura (alphaTab nativo Android, engine Canvas)
- Play/pause/stop com áudio via AlphaSynth
- Seletor de faixas com nomes corretos
- Toggle layout horizontal/vertical
- Modo prática integrado como bottom sheet na tela de partitura
  - Controle de BPM inicial/final, incremento, repetições
  - Aceleração progressiva com controle real de `playbackSpeed` do alphaTab
- Histórico de sessões com gráfico de evolução
- Impressão de todas as páginas da faixa selecionada (PDF multi-página)
- Waveform visualizer que reage ao áudio real via Android `Visualizer` API
- Visualização waveform apenas no layout horizontal
- Busca por nome de arquivo (mínimo 3 caracteres, match em qualquer posição)
- Validação de arquivo: apenas GP abre, outros mostram "Arquivo não compatível"
- Ícone do app na AppBar
- Tema Material 3 com cor primária preta
- Efeitos de áudio (EQ, Reverb, BassBoost, Volume) desabilitados por padrão

### 🔧 Pendente / Melhorias Futuras
- **Fretboard (braço do violão)**: visualização de posições dos dedos
- **Detecção de cifras**: exibição de chord diagrams na partitura
- **Beaming, slurs, dinâmica** nos painters de export
- **Suíte de testes** para parsers e serviços
- **Seleção de SoundFont**: múltiplos `.sf2` configuráveis pelo usuário

### SoundFonts Disponíveis

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `TimGM6mb.sf2` | 6 MB | Usado atualmente (principal) |

## Dependências Principais

- **alphaTab** (`net.alphatab:alphaTab:1.8.2`) - Renderização e áudio (Android)
- **printing** - Exportação e impressão PDF
- **flutter_riverpod** (`^2.6.1`) - Gerenciamento de estado
- **hive / hive_flutter** - Persistência local
- **fl_chart** (`^0.70.2`) - Gráfico de histórico BPM
- **path_provider** - Acesso a diretórios do sistema

## Build

```bash
flutter clean && flutter pub get
flutter run -d android    # Android (recomendado)
```

## Licença

Projeto pessoal — RG Vieira
