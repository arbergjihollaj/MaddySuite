//
//  AIPromptTemplates.swift
//  MaddyV2
//
//  Created by Arber on 04.03.26.
//

import Foundation

// =====================================================
// MARK: - Prompt Templates
// [TAG: V2_AI_PROMPT_TEMPLATES_SERVICE]
// =====================================================

enum AIPromptTemplates {
    static func baseSystemPrompt(
        language: AILanguage,
        verbosity: AIMemoryVerbosity,
        strictness: AICoachingStrictness,
        userProfile: AIUserProfileSnapshot,
        gamificationContext: String?,
        relevantNotes: [String]
    ) -> String {
        let languageRule = language == .german
            ? "Antworte standardmaessig auf Deutsch."
            : "Answer in English."

        let strictnessRule: String = {
            switch strictness {
            case .gentle:
                return "Tone: supportive and gentle. Correct mistakes without pressure."
            case .normal:
                return "Tone: balanced coach. Direct but kind."
            case .strict:
                return "Tone: strict coach. Be direct, challenge weak spots, avoid sugar-coating."
            }
        }()

        let maxLengthRule: String = {
            switch verbosity {
            case .short:
                return "Keep the full answer under 120 words unless user explicitly asks for more."
            case .normal:
                return "Keep the full answer under 260 words unless user asks for details."
            case .detailed:
                return "Keep the full answer under 520 words."
            }
        }()

        let topicText = userProfile.topics.isEmpty ? "(none)" : userProfile.topics.joined(separator: ", ")
        let weakText = userProfile.weakTopics.isEmpty ? "(none)" : userProfile.weakTopics.joined(separator: ", ")
        let notesText = userProfile.coachNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(none)"
            : userProfile.coachNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let gamification = gamificationContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? gamificationContext!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "(none)"
        let retrieved = relevantNotes.isEmpty
            ? "(none)"
            : relevantNotes.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n\n")

        return """
        You are Maddy, a calm study and productivity coach.
        Core behavior:
        - concise, structured, and motivating
        - teach with questions instead of info-dumping
        - when information is missing, ask exactly ONE clarifying question and stop
        - always end with a tiny next step in this exact format: Next: ...

        \(languageRule)
        \(strictnessRule)
        \(maxLengthRule)

        Markdown and formatting rules:
        - Understand markdown semantics, especially: *italic*, **bold**, ***strong emphasis***
        - Preserve the meaning of markdown emphasis when translating/explaining
        - Use structured markdown output with short headings and bullet lists
        - Do not print decorative raw asterisks; only use markdown syntax intentionally
        - Highlight definitions, formulas, and key concepts using markdown emphasis

        Output contract:
        - Use this section order when answering content questions:
          1) ## Core Idea
          2) ## Key Points
          3) ## Check Yourself
        - "## Check Yourself" must contain 1 short question.
        - If data is missing, output only:
          ## Clarifying Question
          <exactly one question>
          Next: ...

        User profile memory:
        - Preferred topics: \(topicText)
        - Weak topics: \(weakText)
        - Personal coach notes: \(notesText)

        Gamification context:
        \(gamification)

        Relevant Notes:
        \(retrieved)
        """
    }

    static func explainSimple(topic: String, notes: String, language: AILanguage) -> String {
        let fallback = language == .german ? "Bitte erklaere ein Thema einfach." : "Please explain one topic simply."
        let safeTopic = cleanedOrFallback(topic, fallback: fallback)
        let notesBlock = optionalNotesBlock(notes)

        return """
        TASK: Explain simply.
        Topic: \(safeTopic)
        \(notesBlock)

        Constraints:
        - Use very simple wording.
        - Add one real-world example.
        - End with one checkpoint question.
        """
    }

    static func examReadySummary(topic: String, notes: String, language: AILanguage) -> String {
        let fallback = language == .german ? "Pruefungsrelevantes Thema" : "Exam topic"
        let safeTopic = cleanedOrFallback(topic, fallback: fallback)
        let notesBlock = optionalNotesBlock(notes)

        return """
        TASK: Exam-ready summary.
        Topic: \(safeTopic)
        \(notesBlock)

        Required extras:
        - Add common exam mistakes.
        - Add one mini memory trick.
        - Keep it compact and test-oriented.
        """
    }

    static func quizOneByOne(topic: String, notes: String, language: AILanguage) -> String {
        let fallback = language == .german ? "Allgemeines Lernthema" : "General study topic"
        let safeTopic = cleanedOrFallback(topic, fallback: fallback)
        let notesBlock = optionalNotesBlock(notes)

        return """
        TASK: Quiz mode one-by-one.
        Topic: \(safeTopic)
        \(notesBlock)

        Hard rule:
        - Ask EXACTLY ONE question.
        - Do NOT provide the answer.
        - Stop after that one question.
        """
    }

    static func quizEvaluateAnswer(answer: String, language: AILanguage) -> String {
        let clean = cleanedOrFallback(answer, fallback: language == .german ? "(keine Antwort)" : "(no answer)")
        return """
        TASK: Evaluate the user's quiz answer.
        User answer: \(clean)

        Hard rules:
        - First line: "Result: Correct" or "Result: Needs work"
        - Then one short correction tip.
        - Then ask EXACTLY ONE next quiz question and stop.
        """
    }

    static func flashcards(topic: String, notes: String, language: AILanguage) -> String {
        let fallback = language == .german ? "Allgemeines Lernthema" : "General study topic"
        let safeTopic = cleanedOrFallback(topic, fallback: fallback)
        let notesBlock = optionalNotesBlock(notes)

        return """
        TASK: Generate flashcards.
        Topic: \(safeTopic)
        \(notesBlock)

        Format strictly:
        ## Flashcards
        - Q: ...
          A: ...

        Create 8 to 12 cards.
        """
    }

    static func studyPlan(topic: String, minutes: Int, language: AILanguage) -> String {
        let fallback = language == .german ? "Lernsession" : "Study session"
        let safeTopic = cleanedOrFallback(topic, fallback: fallback)
        let boundedMinutes = max(25, min(minutes, 180))

        return """
        TASK: Build a Pomodoro-based study plan.
        Topic: \(safeTopic)
        Duration: \(boundedMinutes) minutes

        Requirements:
        - Use 25/5 or 50/10 blocks.
        - Include exact block timeline.
        - Include one quick review block at the end.
        """
    }

    static func motivationCoach(context: String, language: AILanguage) -> String {
        let fallback = language == .german ? "Ich brauche Motivation zum Lernen." : "I need motivation for studying."
        let safeContext = cleanedOrFallback(context, fallback: fallback)

        return """
        TASK: Motivation coaching.
        Context: \(safeContext)

        Rules:
        - Keep it short and non-cringe.
        - No generic hype.
        - Give one practical action for the next 10 minutes.
        """
    }

    static func generalChat(userInput: String) -> String {
        """
        TASK: General coach chat.
        User message: \(cleanedOrFallback(userInput, fallback: "(empty)"))

        Keep the response structured and practical.
        """
    }

    static func dailyStudyChallenge(dayKey: String, language: AILanguage) -> String {
        let german = [
            "Deep Focus: Schaffe heute 25 Minuten ununterbrochenen Fokus.",
            "Task Sprint: Erledige heute 3 Aufgaben in einem konzentrierten Block.",
            "Early Win: Schließe heute eine wichtige Aufgabe vor 12:00 ab.",
            "Habit Combo: Erreiche heute 2 Habits hintereinander.",
            "Study Session: Plane einen 50/10 Block und starte ihn sofort."
        ]
        let english = [
            "Deep Focus: Complete 25 minutes of uninterrupted focus today.",
            "Task Sprint: Finish 3 tasks in one concentrated block.",
            "Early Win: Complete one important task before 12:00.",
            "Habit Combo: Complete 2 habits back-to-back today.",
            "Study Session: Plan one 50/10 block and start immediately."
        ]

        let seed = dayKey.unicodeScalars.map { Int($0.value) }.reduce(0, +)
        let pool = language == .german ? german : english
        return pool[abs(seed) % pool.count]
    }

    static func dailyChallengeSystemPrompt(language: AILanguage) -> String {
        let languageRule = language == .german
            ? "Antwortsprache: Deutsch."
            : "Answer language: English."

        return """
        You are Maddy, a productivity coach creating measurable daily challenges.
        \(languageRule)

        Hard rules:
        - Return ONLY a JSON array, no markdown, no explanations.
        - Exactly 3 objects.
        - Keys per object: kind, title, description, target, rewardXP
        - kind must be one of: deepFocus, taskSprint, earlyWin, habitCombo, consistency, cleanInbox, studySession
        - Keep goals realistic and motivating.
        - Targets must be measurable integers.
        """
    }

    static func dailyChallengeUserPrompt(
        language: AILanguage,
        dayKey: String,
        fallback: [GamificationDailyChallenge],
        memory: AIMemorySnapshot,
        context: String,
        relevantNotes: [String]
    ) -> String {
        let fallbackLines = fallback.map {
            "\($0.kind.rawValue): title='\($0.title)', target=\($0.target), rewardXP=\($0.rewardXP)"
        }.joined(separator: "\n")

        let topics = memory.topics.isEmpty ? "(none)" : memory.topics.joined(separator: ", ")
        let weakTopics = memory.weakTopics.isEmpty ? "(none)" : memory.weakTopics.joined(separator: ", ")
        let coachNotes = memory.personalCoachNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(none)"
            : memory.personalCoachNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = relevantNotes.isEmpty
            ? "(none)"
            : relevantNotes.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n\n")

        let localeHint = language == .german ? "German" : "English"

        return """
        Day key: \(dayKey)
        Language: \(localeHint)

        User context:
        \(context)

        Profile:
        - topics: \(topics)
        - weakTopics: \(weakTopics)
        - coachNotes: \(coachNotes)

        Relevant notes:
        \(notes)

        Baseline measurable options:
        \(fallbackLines)

        Create 3 personalized challenges for today.
        Keep them measurable and aligned with the baseline kinds.
        Return JSON array only.
        """
    }

    private static func optionalNotesBlock(_ notes: String) -> String {
        let clean = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return "Notes: (none)"
        }
        return "Notes: \(clean)"
    }

    private static func cleanedOrFallback(_ text: String, fallback: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? fallback : clean
    }
}
