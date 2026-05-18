import { joinSession } from "@github/copilot-sdk/extension";

const REVIEW_CONTEXT = `Repository Gemini review workflow:
- Check PR review comments, submitted reviews, and issue comments; match both gemini-code-assist and gemini-code-assist[bot].
- After creating or updating a PR, wait for Gemini feedback using the repository's requested polling window before merging.
- If a Gemini review comment requires a fix, address it in code and reply to that specific review thread with "@gemini-code-assist review".
- After requesting rereview, poll again for Gemini's response.
- If Gemini confirms the fix is OK, resolve the corresponding review thread before merging.
- Merge approved PRs with squash merge; put bullet-point details on line 3 and later of the squash commit message body.`;

const REVIEW_PROMPT_PATTERN = /\b(PR|pull request|merge|review|Gemini|gemini-code-assist)\b/i;

await joinSession({
  hooks: {
    onUserPromptSubmitted: async ({ prompt }) => {
      if (!REVIEW_PROMPT_PATTERN.test(prompt)) {
        return {};
      }

      return { additionalContext: REVIEW_CONTEXT };
    },
  },
  tools: [],
});
