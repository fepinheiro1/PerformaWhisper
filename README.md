# PerformaWhisper

Ditado por voz com IA para macOS — inspirado no [Wispr Flow](https://wisprflow.ai), mas com
**transcrição 100% local e privada** (WhisperKit/CoreML rodando no chip do seu Mac).

## Como funciona

1. Segure a tecla de ditado (padrão: **⌃ Control + ⌥ Option**) em qualquer app.
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
- **Limpeza com IA** (OpenAI, `gpt-4o-mini` por padrão e trocável nas Configurações):
  remove "ãh/tipo/né", conserta pontuação e adapta o tom ao app ativo (casual no Slack,
  formal no Mail, literal em editores de código). Sem chave de API, usa limpeza básica
  por regras. A chave fica no Keychain.
- **Dicionário pessoal**: nomes e jargões que o reconhecimento costuma errar.
- **Snippets**: frases faladas que expandem para textos prontos.
- **Histórico** dos últimos 200 ditados com WPM (desligável nas Configurações).
- **Detecção de contexto sem screenshots** — só o nome do app ativo é usado (diferente do
  Wispr Flow, nada de captura de tela).

## Os dois estágios: o que roda local e o que custa dinheiro

O app tem duas etapas independentes, e vale entender a diferença antes de mexer nas
configurações.

| Etapa | Onde roda | O que decide | Custo |
|---|---|---|---|
| **Transcrição** (modelo de voz) | seu Mac | *o que foi ouvido* | grátis, sempre |
| **Limpeza com IA** | OpenAI | *como o texto fica escrito* | ~US$ 0,00014 por ditado |
| **Command Mode** | OpenAI | transforma o texto selecionado | idem, + o texto selecionado |

Sem chave da OpenAI o app continua funcionando: a transcrição é a mesma e a limpeza
cai para um passe por regras. Só o Command Mode fica indisponível.

### Modelo de voz (local, não gasta token)

Escolhido em **Configurações → Geral**. É a rede neural do Whisper que converte áudio em
texto **dentro do seu Mac** — não fala com servidor nenhum e não consome token. O tamanho
é basicamente quantos parâmetros o modelo tem: mais parâmetros entendem melhor sotaque,
ruído e nomes próprios, ao custo de memória e tempo de espera.

Isso importa porque o app é *hold-to-talk*: você solta a tecla e **espera** o texto. O
modelo define essa espera.

| Modelo | Tamanho | Quando usar |
|---|---|---|
| Tiny | ~75 MB | Só para Macs muito fracos; erra bastante em português |
| Base | ~140 MB | Mínimo aceitável em PT-BR — recomendado em Macs Intel |
| **Small** | ~460 MB | Padrão. Equilíbrio honesto em Apple Silicon |
| Medium | ~1,5 GB | Mais preciso e, na prática, o mais lento da lista |
| **Large v3 Turbo** | ~1,6 GB | Maior de todos, mas normalmente **mais rápido que o Medium** |

O Large v3 Turbo é o ponto contraintuitivo: é maior que o Medium, porém foi destilado com
muito menos camadas de decodificação, então costuma transcrever mais rápido **e** melhor
num Mac com chip Apple. A ordem da lista sugere o contrário.

Qualidade em **português** melhora bastante com o tamanho — o Whisper foi treinado
majoritariamente em inglês, e Tiny/Base erram concordância e nomes de um jeito que o Small
já não erra. Em Macs Intel, sem Neural Engine, prefira Base.

O modelo é baixado uma vez no primeiro uso e fica em cache; trocar dispara um download novo.

### Custo real da parte que usa a OpenAI

O prompt de sistema tem ~450 tokens e é reenviado a cada ditado, mais ~100 tokens do que
você falou. Com `gpt-4o-mini` isso dá cerca de **7.000 ditados por dólar** — US$ 5 cobrem
algo como 35 mil ditados.

Detalhe contraintuitivo: um modelo de voz **pior** tende a gastar um pouco *mais* de token,
porque transcrição ruim gera texto mais longo e confuso para limpar. Modelo de voz maior
não encarece a conta.

### Trocando o modelo de texto da OpenAI

Ids de modelo são aposentados de tempos em tempos. Por isso o modelo não é fixo no código:
edite em **Configurações → IA** (padrão `gpt-4o-mini`, botão "Padrão" restaura). A lista
atual fica em [platform.openai.com/docs/models](https://platform.openai.com/docs/models).

Se o id configurado deixar de existir, o ditado normal **continua funcionando** — ele cai na
limpeza por regras — e o app avisa qual modelo falhou. Só o Command Mode fica fora do ar até
você trocar o id.

## Privacidade

Seu áudio nunca sai do Mac: a transcrição é local. Com chave da OpenAI configurada, o que é
enviado é apenas **texto** — o transcrito, as palavras do seu dicionário pessoal (para
corrigir grafias) e, no Command Mode, o trecho que você selecionou. O nome do app ativo é
usado só para escolher o tom, e nunca há captura de tela.

O histórico dos últimos 200 ditados fica em texto puro em
`~/Library/Application Support/PerformaWhisper/` e pode ser desligado em
**Configurações → Geral**. A chave da OpenAI fica no Keychain, não em UserDefaults.

## Build

```sh
swift build            # debug, só a arquitetura da máquina
./make-app.sh          # release universal, gera build/PerformaWhisper.app assinado ad-hoc
```

O `make-app.sh` compila `arm64` e `x86_64` em separado (`swift build --triple`) e une os
dois com `lipo`, então o mesmo `.app` roda em Apple Silicon e em Macs Intel. A variante
`swift build --arch arm64 --arch x86_64` não serve aqui: ela exige o Xcode completo,
enquanto o caminho com `--triple` funciona só com as Command Line Tools. Se uma das
arquiteturas falhar, o script avisa e segue com a outra.

Requisitos: macOS 13+, Swift 5.9+ (Command Line Tools bastam). Roda em Intel, mas sem
Neural Engine a transcrição é bem mais lenta — veja a recomendação de modelo acima.

## Permissões

- **Microfone** — capturar sua voz.
- **Acessibilidade** — detectar a tecla de atalho global e colar o texto no cursor
  (Ajustes do Sistema → Privacidade e Segurança → Acessibilidade).

O onboarding do app guia as duas permissões na primeira execução.

## Testes de linha de comando

```sh
.build/debug/PerformaWhisper --test-transcribe audio.wav   # transcreve um arquivo wav
```
