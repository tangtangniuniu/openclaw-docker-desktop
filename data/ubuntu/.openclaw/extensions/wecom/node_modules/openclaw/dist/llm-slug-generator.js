import { a as resolveAgentDir, c as resolveAgentWorkspaceDir, l as resolveDefaultAgentId, o as resolveAgentEffectiveModelPrimary } from "./run-with-concurrency-Cuc1THN9.js";
import "./paths-hfkBoC7i.js";
import { t as createSubsystemLogger } from "./subsystem-C-Cf_MFK.js";
import "./workspace-CaW79EXh.js";
import "./logger-BW8uLq6f.js";
import { Mr as DEFAULT_PROVIDER, l as parseModelRef } from "./model-selection-BU6wl1le.js";
import "./github-copilot-token-CQmATy5E.js";
import "./legacy-names-BAf61_0I.js";
import "./thinking-B5B36ffe.js";
import "./tokens-CT3nywWU.js";
import { t as runEmbeddedPiAgent } from "./pi-embedded-C6ITuRXf.js";
import "./plugins-BZr8LJrk.js";
import "./accounts-D4KOSoV2.js";
import "./send-BLQvMYTW.js";
import "./send-DyQ6zcob.js";
import "./deliver-ClGktCjk.js";
import "./diagnostic-B9sgiG77.js";
import "./accounts-cJqOTvBI.js";
import "./image-ops-D4vlUR_L.js";
import "./send-D4CMR9ev.js";
import "./pi-model-discovery--C0FuY_K.js";
import "./pi-embedded-helpers-CkWXaNFn.js";
import "./chrome-u1QjWgKY.js";
import "./frontmatter-CZF6xkL3.js";
import "./skills-B24U0XQQ.js";
import "./path-alias-guards-CouH80Zp.js";
import "./redact-DSv8X-3F.js";
import "./errors-_LEe37ld.js";
import "./fs-safe-DOYVoR6M.js";
import "./proxy-env-BZseFuIl.js";
import "./store-BteyapSQ.js";
import "./paths-Co-u8IhA.js";
import "./tool-images-C0W994KU.js";
import "./image-fMgabouP.js";
import "./audio-transcription-runner-DfRfzdqH.js";
import "./fetch-JzejSI-7.js";
import "./fetch-guard-C3LWD6FT.js";
import "./api-key-rotation-CLI6TxVv.js";
import "./proxy-fetch-CbII9--S.js";
import "./ir-D_UJzvhu.js";
import "./render-7C7EDC8_.js";
import "./target-errors-C8xePsI5.js";
import "./commands-registry-DJWLO-6B.js";
import "./skill-commands-B6iXy7Nx.js";
import "./fetch-CONQGbzL.js";
import "./channel-activity-CVe33Aey.js";
import "./tables-DushlpuO.js";
import "./send-CHthYes-.js";
import "./outbound-attachment-3soL6fn0.js";
import "./send-DYCEGbmH.js";
import "./proxy-BzwL4n0W.js";
import "./manager-DS9FBMMG.js";
import "./query-expansion-DUWWrH-g.js";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
//#region src/hooks/llm-slug-generator.ts
/**
* LLM-based slug generator for session memory filenames
*/
const log = createSubsystemLogger("llm-slug-generator");
/**
* Generate a short 1-2 word filename slug from session content using LLM
*/
async function generateSlugViaLLM(params) {
	let tempSessionFile = null;
	try {
		const agentId = resolveDefaultAgentId(params.cfg);
		const workspaceDir = resolveAgentWorkspaceDir(params.cfg, agentId);
		const agentDir = resolveAgentDir(params.cfg, agentId);
		const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-slug-"));
		tempSessionFile = path.join(tempDir, "session.jsonl");
		const prompt = `Based on this conversation, generate a short 1-2 word filename slug (lowercase, hyphen-separated, no file extension).

Conversation summary:
${params.sessionContent.slice(0, 2e3)}

Reply with ONLY the slug, nothing else. Examples: "vendor-pitch", "api-design", "bug-fix"`;
		const modelRef = resolveAgentEffectiveModelPrimary(params.cfg, agentId);
		const parsed = modelRef ? parseModelRef(modelRef, DEFAULT_PROVIDER) : null;
		const provider = parsed?.provider ?? "anthropic";
		const model = parsed?.model ?? "claude-opus-4-6";
		const result = await runEmbeddedPiAgent({
			sessionId: `slug-generator-${Date.now()}`,
			sessionKey: "temp:slug-generator",
			agentId,
			sessionFile: tempSessionFile,
			workspaceDir,
			agentDir,
			config: params.cfg,
			prompt,
			provider,
			model,
			timeoutMs: 15e3,
			runId: `slug-gen-${Date.now()}`
		});
		if (result.payloads && result.payloads.length > 0) {
			const text = result.payloads[0]?.text;
			if (text) return text.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 30) || null;
		}
		return null;
	} catch (err) {
		const message = err instanceof Error ? err.stack ?? err.message : String(err);
		log.error(`Failed to generate slug: ${message}`);
		return null;
	} finally {
		if (tempSessionFile) try {
			await fs.rm(path.dirname(tempSessionFile), {
				recursive: true,
				force: true
			});
		} catch {}
	}
}
//#endregion
export { generateSlugViaLLM };
