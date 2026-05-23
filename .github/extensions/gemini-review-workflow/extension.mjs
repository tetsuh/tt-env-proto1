import { joinSession } from "@github/copilot-sdk/extension";

const REVIEW_CONTEXT = `Repository AI review workflow:
- Check PR review comments, submitted reviews, and issue comments.
- For Gemini, match both gemini-code-assist and gemini-code-assist[bot].
- For GitHub Copilot review, match review authors shown as Copilot.
- After first creating a PR, poll for Gemini or GitHub Copilot review feedback every 1 minute for up to 8 minutes before proceeding.
- If a Gemini review comment requires a fix, address it in code and reply to that specific review thread with "/gemini review".
- If a GitHub Copilot review comment requires a fix, address it in code and request Copilot rereview using the GitHub-supported Copilot review trigger for that PR.
- After pushing fixes for AI review feedback, explicitly request Gemini or GitHub Copilot rereview before polling; polling alone does not trigger rereview.
- After requesting rereview, poll for Gemini or GitHub Copilot review feedback every 1 minute for up to 8 minutes before proceeding.
- If Gemini or GitHub Copilot confirms the fix is OK, resolve the corresponding review thread before merging.
- Do not merge PRs automatically; when a PR is mergeable, report the status and let the user decide whether to merge.
- If the user approves merging, use squash merge with a Conventional Commits title and put bullet-point details on line 3 and later of the squash commit message body.`;

const REVIEW_KEYWORDS = [
  "PRs?",
  "pull requests?",
  "merge(s|ing)?",
  "review(s|ing)?",
  "Gemini",
  "Copilot",
];
const REVIEW_PROMPT_PATTERN = new RegExp(`\\b(${REVIEW_KEYWORDS.join("|")})\\b`, "i");

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
