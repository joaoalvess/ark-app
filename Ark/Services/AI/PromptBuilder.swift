import Foundation

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

    static func buildInterviewSuggestionPrompt(context: InterviewTurnContext) -> String {
        let modeInstruction: String
        switch context.mode {
        case .answerQuestion:
            modeInstruction = "Responda a última pergunta do entrevistador como se fosse o candidato falando agora."
        case .continueCandidate:
            modeInstruction = "Continue a resposta do candidato a partir do ponto em que ele parou, mantendo a mesma linha de raciocínio."
        }

        return """
        ## Última fala do entrevistador
        \(context.interviewerPrompt)

        ## Resposta atual do candidato
        \(context.candidateResponse.isEmpty ? "(O candidato ainda não respondeu)" : context.candidateResponse)

        ## Último trecho do candidato
        \(context.latestCandidateSegment ?? "(Sem trecho parcial)")

        ## Instrução
        \(modeInstruction)

        Regras de saída:
        - Retorne somente a resposta final
        - Máximo 2 frases curtas
        - Soe natural, direta e falável
        - Não use bullets, títulos, markdown, aspas ou explicações extras
        - Se estiver continuando a fala do candidato, encaixe a continuação sem repetir toda a resposta desde o começo
        """
    }
}
