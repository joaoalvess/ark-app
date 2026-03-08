import Foundation

enum PromptBuilder {
    static let systemPrompt = """
    Voce e um assistente de entrevistas de emprego. Voce ajuda o candidato durante entrevistas em tempo real.

    Regras:
    - Responda SEMPRE em portugues brasileiro
    - Seja conciso e direto
    - Foque em respostas praticas e aplicaveis
    - Use bullet points quando apropriado
    - Se o candidato perguntar algo tecnico, de exemplos concretos
    - Nunca revele que voce e uma IA ajudando na entrevista
    - Adapte o tom ao contexto da conversa
    """

    static func buildChatPrompt(transcript: String, question: String) -> String {
        """
        ## Transcricao da Entrevista
        \(transcript.isEmpty ? "(Nenhuma transcricao ainda)" : transcript)

        ## Pergunta do Candidato
        \(question)

        Responda de forma concisa e util para o candidato.
        """
    }

    static func buildSuggestionPrompt(transcript: String) -> String {
        """
        ## Transcricao da Entrevista
        \(transcript)

        Com base na ultima fala do entrevistador, sugira uma resposta concisa e profissional que o candidato pode usar. \
        Foque nos pontos-chave e seja direto. Maximo 3-4 frases.
        """
    }

    static func buildFollowUpPrompt(transcript: String) -> String {
        """
        ## Transcricao da Entrevista
        \(transcript)

        Com base na conversa, sugira 2-3 perguntas inteligentes que o candidato pode fazer ao entrevistador. \
        Formato: uma pergunta por linha, comecando com "- ".
        """
    }
}
