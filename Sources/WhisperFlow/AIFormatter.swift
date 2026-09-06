import Foundation

/// Cleans up raw transcripts: removes filler words, fixes punctuation and
/// adapts tone. Uses the OpenAI API when a key is configured, otherwise
/// falls back to rule-based cleanup.
enum AIFormatter {

    // MARK: - Public entry points

    /// Cleanup pass applied to every dictation.
    static func cleanup(_ raw: String, context: ActiveAppContext) async -> String {
        let cleaned: String
        if Preferences.shared.aiCleanupEnabled, !Preferences.shared.openAIKey.isEmpty {
            do {
                cleaned = try await callOpenAI(
                    system: cleanupSystemPrompt(context: context),
                    user: raw
                )
            } catch {
                NSLog("WhisperFlow: OpenAI falhou (\(error.localizedDescription)); usando limpeza por regras")
                cleaned = ruleBasedCleanup(raw)
            }
        } else {
            cleaned = ruleBasedCleanup(raw)
        }

        // Snippets expand last: the model is told to rewrite and restructure, so
        // expanding first let it reformat things like e-mail signatures.
        return DataStore.shared.applySnippets(to: cleaned)
    }

    /// Command Mode: applies a spoken instruction to the selected text.
    static func applyCommand(instruction: String, to selectedText: String) async throws -> String {
        guard !Preferences.shared.openAIKey.isEmpty else {
            throw NSError(domain: "WhisperFlow", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Command Mode requer uma chave da OpenAI nas configurações"
            ])
        }
        let system = """
        You are a text editing assistant. The user selected a piece of text and spoke an instruction \
        about how to transform it. Apply the instruction and return ONLY the transformed text, \
        with no preamble, no quotes, no explanations. Keep the original language of the text \
        unless the instruction asks to translate.
        """
        let user = "INSTRUCTION: \(instruction)\n\nTEXT:\n\(selectedText)"
        return try await callOpenAI(system: system, user: user)
    }

    // MARK: - Prompts

    private static func cleanupSystemPrompt(context: ActiveAppContext) -> String {
        let tonePref = Preferences.shared.tone
        let tone = tonePref == .auto ? context.suggestedTone : tonePref
        let toneDescription: String
        switch tone {
        case .veryCasual: toneDescription = "very casual and relaxed"
        case .casual: toneDescription = "casual and friendly"
        case .formal: toneDescription = "professional and polished"
        default: toneDescription = "neutral"
        }

        var prompt = """
        You clean up raw speech-to-text transcripts for dictation software. The user dictated text \
        that will be inserted into the app "\(context.appName)". Rewrite the transcript as clean \
        written text:
        - Remove filler words and hesitations (uh, um, ãh, é..., tipo, like, you know, né).
        - Remove false starts and self-corrections, keeping only the final intent.
        - Fix punctuation, capitalization and obvious speech-recognition errors.
        - Keep the SAME language as the transcript. Never translate.
        - STRUCTURE the text the way the speaker clearly intends: if they enumerate items \
        ("primeiro... segundo...", "são três coisas: ...", "one, two, three"), format them as a list \
        with one item per line (use "- " bullets or "1." numbers as appropriate). Announcement phrases \
        like "vou listar três coisas:" stay as an intro line before the list.
        - Break long dictations into paragraphs at natural topic changes.
        - Obey spoken formatting commands and remove them from the output: "nova linha"/"new line" \
        → line break; "novo parágrafo"/"new paragraph" → blank line; "em tópicos" → bullet list.
        - Do NOT add information, do NOT answer questions in the text, do NOT summarize. \
        Output only the cleaned text, nothing else.
        - Target tone: \(toneDescription).
        """
        if context.isCodeEditor {
            prompt += "\n- The target is a code editor/terminal: keep the text plain and literal, no markdown."
        }
        let words = DataStore.shared.dictionaryWords.filter { !$0.isEmpty }
        if !words.isEmpty {
            prompt += "\n- The user often mentions these names/terms; fix misrecognitions of them: \(words.joined(separator: ", "))."
        }
        return prompt
    }

    // MARK: - OpenAI call

    private static func callOpenAI(system: String, user: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Preferences.shared.openAIKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "erro desconhecido"
            throw NSError(domain: "WhisperFlow", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI: \(msg.prefix(200))"])
        }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw NSError(domain: "WhisperFlow", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Resposta vazia da OpenAI"])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rule-based fallback

    /// Hesitations that are not real words in any language we transcribe.
    private static let commonFillers = ["ãh", "aham", "hum", "hmm", "né", "tipo assim",
                                        "uh", "uhm", "erm", "you know"]

    /// Ambiguous outside English: "um" is the Portuguese indefinite article and
    /// "ah" a normal interjection, so stripping them mangles PT-BR dictation.
    private static let englishOnlyFillers = ["um", "ah"]

    static func ruleBasedCleanup(_ text: String,
                                 language: String = Preferences.shared.language) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }

        var fillers = commonFillers
        if language == "en" { fillers += englishOnlyFillers }

        for f in fillers {
            t = t.replacingOccurrences(
                of: #"(?i)(^|[\s,])\#(NSRegularExpression.escapedPattern(for: f))($|[\s,.!?])"#,
                with: "$1$2",
                options: .regularExpression
            )
        }
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)

        // Removing a filler can leave punctuation stranded ("tipo assim, sabe, né"
        // → ", sabe,"), so repair the seams before finishing the sentence.
        t = t.replacingOccurrences(of: #"^[\s,;:.]+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(,\s*){2,}"#, with: ", ", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*([.!?])"#, with: "$1", options: .regularExpression)
        // Allow for the trailing space a removed filler leaves behind.
        t = t.replacingOccurrences(of: #"[,;:]+\s*$"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }

        if let first = t.first, first.isLowercase {
            t = first.uppercased() + t.dropFirst()
        }
        if let last = t.last, !".!?…\"')".contains(last) {
            t += "."
        }
        return t
    }
}
