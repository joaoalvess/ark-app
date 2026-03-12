import Foundation

enum VoiceAction: String, CaseIterable {
    case assist
    case whatToSay
    case followUp
    case recap
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

    static func buildSuggestionPrompt(profile: AssistantProfile, transcript: String) -> String {
        let instruction: String
        switch profile {
        case .generalist:
            instruction = """
            Com base na última fala do interlocutor, sugira uma resposta pronta que o usuário pode falar diretamente. \
            A resposta deve soar natural e profissional. Máximo 3-4 frases.
            """

        case .code:
            instruction = """
            Com base na última parte da discussão, forneça pontos-chave técnicos relevantes. \
            Inclua snippets de código quando apropriado. Seja direto e técnico.
            """

        case .techInterview:
            instruction = """
            Com base na última pergunta do entrevistador, sugira uma resposta curta, natural e pronta para o candidato falar. \
            Máximo 2 frases, sem bullets e sem explicações extras.
            """
        }

        return """
        ## Transcrição
        \(transcript)

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
            Com base no contexto da entrevista, sugira algo relevante que o candidato \
            poderia acrescentar à conversa agora — um insight, exemplo ou ponto complementar. \
            Máximo 2 frases curtas e naturais.
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
        // .assist
        case (.assist, .techInterview):
            instruction = "Analise a última pergunta ou tema da entrevista e dê ao candidato a melhor estratégia de resposta. Diga o que enfatizar e o que evitar. 2-3 frases diretas, sem formatação."
        case (.assist, .code):
            instruction = "Analise o ponto técnico em discussão e dê orientação prática ao desenvolvedor. Aponte o que é mais relevante ou o que pode estar faltando. 2-3 frases diretas."
        case (.assist, .generalist):
            instruction = "Analise o contexto da conversa e dê orientação prática ao usuário. Foque no que é mais relevante para o momento. 2-3 frases diretas."

        // .whatToSay
        case (.whatToSay, .techInterview):
            instruction = "O candidato precisa de ajuda para continuar ou completar sua resposta ao entrevistador. Continue o raciocínio dele de forma natural, como se estivesse concluindo o pensamento. Comece com '...' para indicar continuação. 2-3 frases prontas para falar, naturais e confiantes. Sem bullets, sem markdown, sem explicações — apenas a continuação da fala."
        case (.whatToSay, .code):
            instruction = "O desenvolvedor precisa de ajuda para continuar ou completar sua fala. Continue o raciocínio dele de forma natural, concluindo o ponto técnico. Comece com '...' para indicar continuação. 2-3 frases prontas para falar."
        case (.whatToSay, .generalist):
            instruction = "O usuário precisa de ajuda para continuar ou completar sua fala. Continue o raciocínio dele de forma natural, como se estivesse concluindo o pensamento. Comece com '...' para indicar continuação. 2-3 frases prontas para falar."

        // .followUp
        case (.followUp, .techInterview):
            instruction = "Sugira uma pergunta ou comentário inteligente que o candidato pode fazer agora para demonstrar interesse e profundidade técnica. 1-2 frases naturais, prontas para falar."
        case (.followUp, .code):
            instruction = "Sugira uma pergunta técnica ou consideração de design relevante que o desenvolvedor pode trazer agora. 1-2 frases diretas."
        case (.followUp, .generalist):
            instruction = "Sugira uma pergunta ou comentário relevante que o usuário pode fazer agora para avançar a conversa. 1-2 frases naturais."

        // .recap
        case (.recap, .techInterview):
            instruction = "Resuma os pontos principais discutidos na entrevista até agora: perguntas feitas, temas abordados e como o candidato se saiu. 2-3 frases diretas."
        case (.recap, .code):
            instruction = "Resuma os pontos técnicos discutidos até agora: decisões tomadas, problemas identificados e próximos passos. 2-3 frases diretas."
        case (.recap, .generalist):
            instruction = "Resuma os pontos principais da conversa até agora. 2-3 frases diretas."
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
