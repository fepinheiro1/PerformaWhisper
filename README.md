# WhisperFlow

Ditado por voz com IA para macOS — inspirado no [Wispr Flow](https://wisprflow.ai), mas com
**transcrição 100% local e privada** (WhisperKit/CoreML rodando no chip do seu Mac).

## Como funciona

1. Segure a tecla de ditado (padrão: **⌥ Option direita**) em qualquer app.
2. Fale naturalmente. Uma pílula na base da tela mostra que está ouvindo.
3. Solte a tecla: o texto transcrito, limpo e pontuado é inserido onde o cursor está.
4. **Esc** cancela um ditado em andamento.

### Command Mode

Selecione um texto em qualquer app, segure a tecla de comando (padrão: **⌘ Command direita**)
e fale uma instrução: *"deixe mais formal"*, *"traduza para inglês"*, *"transforme em lista"*.
O texto selecionado é substituído pelo resultado. (Requer chave da OpenAI.)

## Funcionalidades

- **Transcrição local** com WhisperKit (modelos tiny → large-v3 turbo), sem internet e sem
  enviar seu áudio para lugar nenhum.
- **Limpeza com IA** (OpenAI `gpt-4o-mini`): remove "ãh/tipo/né", conserta pontuação e adapta
  o tom ao app ativo (casual no Slack, formal no Mail, literal em editores de código).
  Sem chave de API, usa limpeza básica por regras.
- **Dicionário pessoal**: nomes e jargões que o reconhecimento costuma errar.
- **Snippets**: frases faladas que expandem para textos prontos.
- **Histórico** dos últimos 200 ditados com WPM.
- **Detecção de contexto sem screenshots** — só o nome do app ativo é usado (diferente do
  Wispr Flow, nada de captura de tela).

## Build

```sh
swift build            # debug
./make-app.sh          # gera build/WhisperFlow.app (release, assinado ad-hoc)
```

Requisitos: macOS 14+, Apple Silicon recomendado, Swift 6 (Command Line Tools bastam).

## Permissões

- **Microfone** — capturar sua voz.
- **Acessibilidade** — detectar a tecla de atalho global e colar o texto no cursor
  (Ajustes do Sistema → Privacidade e Segurança → Acessibilidade).

O onboarding do app guia as duas permissões na primeira execução.

## Testes de linha de comando

```sh
.build/debug/WhisperFlow --whisper-info                 # confirma o link do WhisperKit
.build/debug/WhisperFlow --test-transcribe audio.wav     # transcreve um arquivo
```
