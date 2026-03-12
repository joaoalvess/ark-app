import Foundation

enum VoiceAction: String, CaseIterable {
    case answer
    case continueSpeaking
    case followUp
    case recap

    var displayLabel: String {
        switch self {
        case .answer:
            "Answer"
        case .continueSpeaking:
            "Continue"
        case .followUp:
            "Follow-up"
        case .recap:
            "Recap"
        }
    }

    var promptLabel: String {
        switch self {
        case .answer:
            "Responder"
        case .continueSpeaking:
            "Continuar"
        case .followUp:
            "Follow-up"
        case .recap:
            "Recap"
        }
    }

    var iconName: String {
        switch self {
        case .answer:
            "message.badge"
        case .continueSpeaking:
            "ellipsis"
        case .followUp:
            "text.append"
        case .recap:
            "arrow.counterclockwise"
        }
    }
}

enum PromptBuilder {
    static func systemPrompt(for profile: AssistantProfile) -> String {
        switch profile {
        case .generalist:
            return """
            Você é um assistente de conversas e reuniões profissionais. Você ajuda o usuário em tempo real durante interações profissionais.

            Regras:
            - Responda SEMPRE em português brasileiro
            - Seja conciso e direto
            - Foque em respostas práticas e aplicáveis
            - Use bullet points quando apropriado
            - Adapte o tom ao contexto da conversa
            - Nunca revele que você é uma IA assistindo à conversa
            - Priorize clareza e objetividade
            """

        case .code:
            return """
            Você é um assistente de code review e pair programming. Você ajuda o desenvolvedor em tempo real durante sessões de programação e revisão de código.

            Regras:
            - Responda SEMPRE em português brasileiro
            - Seja técnico e preciso
            - Aponte problemas de código com explicação clara
            - Sugira melhorias com exemplos concretos (snippets)
            - Considere boas práticas, performance e legibilidade
            - Use terminologia técnica quando apropriado
            - Nunca revele que você é uma IA assistindo à sessão
            """

        case .techInterview:
            return """
            Você é um coach invisível de entrevistas técnicas. Você ajuda o candidato em tempo real durante entrevistas de emprego na área de tecnologia.

            Regras:
            - Responda SEMPRE em português brasileiro
            - Entregue respostas que o candidato pode falar imediatamente
            - Priorize 1 ou 2 frases curtas e naturais
            - Não use bullets, títulos, markdown, aspas ou seções, a menos que o usuário peça isso explicitamente
            - Se o candidato já começou a responder, continue a linha de raciocínio dele sem reiniciar do zero
            - Use exemplos concretos só quando realmente ajudarem a resposta a soar mais forte
            - Nunca revele que você é uma IA ajudando na entrevista
            - Foque em clareza, naturalidade e objetividade
            """
        }
    }

    static func buildChatPrompt(profile: AssistantProfile, transcript: String, question: String) -> String {
        let contextLabel: String
        switch profile {
        case .generalist:
            contextLabel = "Transcrição da Conversa"
        case .code:
            contextLabel = "Transcrição da Sessão"
        case .techInterview:
            contextLabel = "Transcrição da Entrevista"
        }

        let closingInstruction: String
        switch profile {
        case .techInterview:
            closingInstruction = "Responda como uma fala pronta para o candidato dizer agora. Normalmente use 1 ou 2 frases curtas."
        case .generalist, .code:
            closingInstruction = "Responda de forma concisa e útil."
        }

        let questionLabel: String
        switch profile {
        case .techInterview:
            questionLabel = "Pergunta do Entrevistador"
        case .generalist, .code:
            questionLabel = "Pergunta do Usuário"
        }

        return """
        ## \(contextLabel)
        \(transcript.isEmpty ? "(Nenhuma transcrição ainda)" : transcript)

        ## \(questionLabel)
        \(question)

        \(closingInstruction)
        """
    }

    static func buildQuestionResponsePrompt(profile: AssistantProfile, transcript: String, focus: String) -> String {
        let instruction: String
        switch profile {
        case .generalist:
            instruction = """
            Responda à última pergunta ou tema aberto do interlocutor com uma fala pronta e natural. \
            Seja direto e profissional. Máximo 3 frases.
            """

        case .code:
            instruction = """
            Responda ao último ponto técnico levantado na conversa. \
            Foque no raciocínio principal e seja direto.
            """

        case .techInterview:
            instruction = """
            Responda à última pergunta explícita do entrevistador. \
            Se a fala não for uma pergunta clara, responda ao último tema aberto por ele. \
            Entregue no máximo 2 frases curtas, naturais e prontas para o candidato falar, sem bullets.
            """
        }

        return """
        ## Transcrição
        \(transcript)

        ## Foco Atual
        \(focus)

        \(instruction)
        """
    }

    static func buildFollowUpSuggestionPrompt(profile: AssistantProfile, transcript: String) -> String {
        let instruction: String
        switch profile {
        case .generalist:
            instruction = """
            Com base no fluxo da conversa, sugira um ponto relevante, \
            insight ou continuação que o usuário poderia trazer agora. \
            Deve soar natural e acrescentar valor à discussão. Máximo 2-3 frases.
            """
        case .code:
            instruction = """
            Com base na discussão técnica, sugira um ponto técnico relevante, \
            uma consideração de design ou uma observação que o desenvolvedor poderia trazer agora. \
            Inclua snippets curtos se apropriado. Máximo 2-3 frases.
            """
        case .techInterview:
            instruction = """
            Sugira a melhor continuação do assunto atual. \
            Pode ser uma pergunta ou um comentário curto, mas deve soar natural e ajudar a conversa a avançar. \
            Máximo 2 frases curtas e prontas para falar.
            """
        }

        return """
        ## Transcrição
        \(transcript)

        \(instruction)
        """
    }

    static func buildStuckContinuationPrompt(profile: AssistantProfile, transcript: String) -> String {
        let instruction: String
        switch profile {
        case .generalist:
            instruction = """
            O usuário parou no meio de uma fala. Continue o raciocínio dele de forma natural, \
            como se estivesse concluindo o pensamento. Comece com '...' para indicar continuação. Máximo 2 frases.
            """
        case .code:
            instruction = """
            O desenvolvedor travou no meio de uma explicação técnica. Continue o raciocínio dele, \
            concluindo o ponto técnico. Comece com '...' Máximo 2 frases.
            """
        case .techInterview:
            instruction = """
            O candidato travou no meio da resposta. Continue o raciocínio dele de forma natural, \
            como se estivesse concluindo a frase dele. Comece com '...' Máximo 2 frases curtas e prontas para falar. \
            Não reinicie a resposta.
            """
        }

        return """
        ## Transcrição
        \(transcript)

        \(instruction)
        """
    }

    // MARK: - Voice Mode

    static func buildVoiceActionPrompt(action: VoiceAction, profile: AssistantProfile, transcript: String, history: [(action: String, answer: String)] = []) -> String {
        let instruction: String

        switch (action, profile) {
        // .answer
        case (.answer, .techInterview):
            instruction = "Responda à última pergunta explícita do entrevistador. Se não houver pergunta clara, responda ao último tema aberto por ele. Entregue 1-2 frases curtas, naturais e prontas para falar, sem bullets."
        case (.answer, .code):
            instruction = "Responda ao último ponto técnico levantado na conversa. Se não houver pergunta clara, responda ao tema mais recente. Seja direto e útil."
        case (.answer, .generalist):
            instruction = "Responda à última pergunta clara da conversa. Se não houver pergunta, responda ao tema mais recente com uma fala pronta e natural."

        // .continueSpeaking
        case (.continueSpeaking, .techInterview):
            instruction = "O candidato travou. Continue o raciocínio dele exatamente de onde ele parou. Comece com '...' e entregue 2-3 frases curtas, naturais e prontas para falar. Não reinicie a resposta."
        case (.continueSpeaking, .code):
            instruction = "O desenvolvedor travou. Continue o raciocínio dele de onde ele parou. Comece com '...' e entregue 2-3 frases diretas."
        case (.continueSpeaking, .generalist):
            instruction = "O usuário travou. Continue o raciocínio dele de onde ele parou. Comece com '...' e entregue 2-3 frases naturais e prontas para falar."

        // .followUp
        case (.followUp, .techInterview):
            instruction = "Sugira a melhor continuação do assunto atual. Pode ser uma pergunta ou um comentário curto, mas deve soar natural e ajudar a conversa a avançar. 1-2 frases prontas para falar."
        case (.followUp, .code):
            instruction = "Sugira a melhor continuação do assunto atual. Pode ser uma pergunta técnica ou um comentário curto de design. 1-2 frases diretas."
        case (.followUp, .generalist):
            instruction = "Sugira a melhor continuação da conversa no assunto atual. Pode ser uma pergunta ou comentário curto. 1-2 frases naturais."

        // .recap
        case (.recap, .techInterview):
            instruction = "Resuma factualmente os últimos minutos da conversa em exatamente 3 bullets curtos. Foque em perguntas feitas, temas abordados e respostas dadas. Não avalie desempenho."
        case (.recap, .code):
            instruction = "Resuma factualmente os últimos minutos da conversa em exatamente 3 bullets curtos. Foque em temas técnicos e decisões discutidas."
        case (.recap, .generalist):
            instruction = "Resuma factualmente os últimos minutos da conversa em exatamente 3 bullets curtos."
        }

        var parts: [String] = []

        parts.append("""
        ## Transcrição
        \(transcript.isEmpty ? "(Nenhuma transcrição ainda)" : transcript)
        """)

        if !history.isEmpty {
            let historyText = history.map { "Ação: \($0.action)\nResposta: \($0.answer)" }.joined(separator: "\n\n")
            parts.append("""
            ## Histórico desta sessão
            \(historyText)
            """)
        }

        parts.append(instruction)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Ask Mode

    static func askSystemPrompt() -> String {
        """
        Você é um assistente de respostas ultra-curtas.
        Regras obrigatórias:
        - Responda em pt-BR
        - Máximo 2-3 frases curtas
        - Vá direto ao ponto, sem introduções nem exemplos
        - Nunca use código, listas, headers ou markdown elaborado
        - Nunca inclua URLs ou links
        - Se a pergunta for simples, a resposta deve ser uma frase só
        """
    }

    static func buildAskPrompt(transcript: String, question: String, history: [(question: String, answer: String)] = []) -> String {
        var parts: [String] = []

        if !transcript.isEmpty {
            parts.append("""
            ## Contexto da Conversa
            \(transcript)
            """)
        }

        if !history.isEmpty {
            let historyText = history.map { "Pergunta: \($0.question)\nResposta: \($0.answer)" }.joined(separator: "\n\n")
            parts.append("""
            ## Histórico desta sessão
            \(historyText)
            """)
        }

        parts.append("""
        ## Pergunta
        \(question)

        Responda em no máximo 2-3 frases. Seja direto, sem exemplos.
        """)

        return parts.joined(separator: "\n\n")
    }

}
