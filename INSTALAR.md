# PerformaWhisper — Instruções de instalação

Ditado por voz com IA para Mac: segure um atalho, fale, solte — e o texto aparece
polido onde seu cursor estiver, em qualquer aplicativo. A transcrição roda **100%
localmente no seu Mac** (nada de áudio indo para a nuvem).

## Requisitos

- macOS 13 (Ventura) ou mais novo
- Funciona em Macs com chip Apple (M1/M2/M3/M4) **e** em Macs Intel
- Internet só na primeira execução (para baixar o modelo de voz) e,
  opcionalmente, para a formatação com IA

> **Mac Intel?** Funciona, mas a transcrição é mais lenta (o chip não tem o motor
> neural dos Macs M). Dica: em **Configurações → Geral → Modelo de voz**, escolha
> **Base** ou **Tiny** — ficam bem mais rápidos e ainda têm boa qualidade.

## Instalação (5 minutos)

### 1. Copie o app para a pasta Aplicativos

Descompacte o `PerformaWhisper.zip` (clique duplo) e arraste o **PerformaWhisper.app**
para a pasta **Aplicativos**.

### 2. Libere o app no Gatekeeper

Como o app não vem da App Store, o macOS vai bloqueá-lo na primeira abertura
("não pode ser aberto" ou "está danificado"). Para liberar, abra o **Terminal**
(⌘Espaço → digite "Terminal") e cole este comando:

```sh
xattr -cr /Applications/PerformaWhisper.app
```

Aperte Enter. Pronto — isso só remove a marca de "arquivo baixado da internet".

### 3. Abra e conceda as permissões

Abra o PerformaWhisper (⌘Espaço → "PerformaWhisper"). Uma janela de boas-vindas vai pedir
duas permissões:

1. **Microfone** — clique em "Permitir" e confirme.
2. **Acessibilidade** — clique em "Permitir"; os Ajustes do Sistema vão abrir.
   Ligue a chavinha do **PerformaWhisper** na lista. Essa permissão é o que deixa o
   app detectar o atalho de teclado e digitar o texto para você.

Volte à janela do app: quando os dois itens estiverem com ✓ verde, clique em
**"Começar a usar"**.

Na primeira execução o app baixa o modelo de voz (~460 MB). O ícone de onda
sonora na barra de menu mostra o progresso; ao terminar aparece
**"Pronto para ditar ✓"**.

## Como usar

| Ação | Como fazer |
|---|---|
| **Ditar** | Clique em qualquer campo de texto, **segure ⌃ Control + ⌥ Option**, fale, e **solte**. O texto entra onde o cursor está. |
| **Cancelar** | Aperte **Esc** enquanto estiver gravando. |
| **Command Mode** | Selecione um texto, **segure ⌘ Command da direita** e fale uma instrução: "deixe mais formal", "traduza para inglês", "transforme em lista". |
| **Configurações** | Clique no ícone de onda sonora na barra de menu (canto superior direito). |

Dicas de ditado: fale naturalmente — o app remove os "ãh", "tipo", "né" e pontua
sozinho. Diga **"nova linha"** ou **"novo parágrafo"** para formatar, e se você
enumerar itens ("primeiro..., segundo..."), ele monta a lista automaticamente.

## Formatação com IA (recomendado)

A transcrição funciona sem internet, mas a formatação inteligente (limpeza de
vícios de fala, listas, tom adaptado ao app) usa a API da OpenAI:

1. Crie uma chave em <https://platform.openai.com/api-keys> (conta com crédito;
   US$ 5 duram meses — cada ditado custa fração de centavo).
2. Ícone da barra de menu → **Configurações → aba IA** → cole a chave.

Sem a chave, o app segue funcionando com uma limpeza básica (o Command Mode,
porém, fica indisponível).

## Ajustes úteis

- **Configurações → Geral**: trocar o atalho (Control+Option, Option direita, Fn…),
  o idioma e o modelo de voz (modelos maiores = mais precisão, mais lentos).
- **Dicionário**: adicione nomes próprios e jargões que o reconhecimento erra.
- **Snippets**: frases faladas que viram textos prontos (ex.: "assinatura de
  e-mail" → sua assinatura completa).
- **Abrir junto com o Mac**: Ajustes do Sistema → Geral → Itens de Início de
  Sessão → "+" → PerformaWhisper.

## Problemas comuns

- **Seguro o atalho e nada acontece** → a Acessibilidade não está valendo. Vá em
  Ajustes do Sistema → Privacidade e Segurança → Acessibilidade, desligue e ligue
  a chavinha do PerformaWhisper, e reabra o app.
- **"Modelo ainda carregando…"** → aguarde o download terminar (barra de menu
  mostra o progresso).
- **Texto não aparece no app de destino** → alguns campos protegidos (senhas)
  bloqueiam colagem; teste primeiro nas Notas.

---

*Privacidade: seu áudio nunca sai do Mac — a transcrição é local. Com a chave da
OpenAI configurada, apenas o texto transcrito é enviado para formatação.*
