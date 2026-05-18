import { joinSession } from "@github/copilot-sdk/extension";

const REVIEW_CONTEXT = `Repository AI review workflow:
- Check PR review comments, submitted reviews, and issue comments.
- For Gemini, match both gemini-code-assist and gemini-code-assist[bot].
- For GitHub Copilot review, match review authors whose login/name clearly identifies GitHub Copilot, such as github-copilot[bot] or Copilot.
- After first creating a PR, poll for Gemini or GitHub Copilot review feedback every 1 minute for up to 8 minutes before proceeding.
- If a Gemini review comment requires a fix, address it in code and reply to that specific review thread with "@gemini-code-assist review".
- If a GitHub Copilot review comment requires a fix, address it in code and request Copilot rereview using the GitHub-supported Copilot review trigger for that PR.
- After requesting rereview, poll for Gemini or GitHub Copilot review feedback every 1 minute for up to 8 minutes before proceeding.
- If Gemini or GitHub Copilot confirms the fix is OK, resolve the corresponding review thread before merging.
- Do not merge PRs automatically; when a PR is mergeable, report the status and let the user decide whether to merge.
- If the user approves merging, use squash merge and put bullet-point details on line 3 and later of the squash commit message body.`;

const REVIEW_PROMPT_PATTERN = /\b(PR|pull request|merge|review|Gemini|gemini-code-assist|Copilot)\b/i;

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
