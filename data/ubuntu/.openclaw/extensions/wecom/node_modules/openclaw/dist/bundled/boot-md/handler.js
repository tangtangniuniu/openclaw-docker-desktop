import { c as resolveAgentWorkspaceDir, r as listAgentIds } from "../../run-with-concurrency-Cuc1THN9.js";
import "../../paths-hfkBoC7i.js";
import { a as defaultRuntime, t as createSubsystemLogger } from "../../subsystem-C-Cf_MFK.js";
import { B as resolveAgentIdFromSessionKey } from "../../workspace-CaW79EXh.js";
import "../../logger-BW8uLq6f.js";
import "../../model-selection-BU6wl1le.js";
import "../../github-copilot-token-CQmATy5E.js";
import { a as isGatewayStartupEvent } from "../../legacy-names-BAf61_0I.js";
import "../../thinking-B5B36ffe.js";
import { n as SILENT_REPLY_TOKEN } from "../../tokens-CT3nywWU.js";
import { o as agentCommand, s as createDefaultDeps } from "../../pi-embedded-C6ITuRXf.js";
import "../../plugins-BZr8LJrk.js";
import "../../accounts-D4KOSoV2.js";
import "../../send-BLQvMYTW.js";
import "../../send-DyQ6zcob.js";
import "../../deliver-ClGktCjk.js";
import "../../diagnostic-B9sgiG77.js";
import "../../accounts-cJqOTvBI.js";
import "../../image-ops-D4vlUR_L.js";
import "../../send-D4CMR9ev.js";
import "../../pi-model-discovery--C0FuY_K.js";
import { Dt as resolveAgentMainSessionKey, W as loadSessionStore, Y as updateSessionStore, kt as resolveMainSessionKey } from "../../pi-embedded-helpers-CkWXaNFn.js";
import "../../chrome-u1QjWgKY.js";
import "../../frontmatter-CZF6xkL3.js";
import "../../skills-B24U0XQQ.js";
import "../../path-alias-guards-CouH80Zp.js";
import "../../redact-DSv8X-3F.js";
import "../../errors-_LEe37ld.js";
import "../../fs-safe-DOYVoR6M.js";
import "../../proxy-env-BZseFuIl.js";
import "../../store-BteyapSQ.js";
import { s as resolveStorePath } from "../../paths-Co-u8IhA.js";
import "../../tool-images-C0W994KU.js";
import "../../image-fMgabouP.js";
import "../../audio-transcription-runner-DfRfzdqH.js";
import "../../fetch-JzejSI-7.js";
import "../../fetch-guard-C3LWD6FT.js";
import "../../api-key-rotation-CLI6TxVv.js";
import "../../proxy-fetch-CbII9--S.js";
import "../../ir-D_UJzvhu.js";
import "../../render-7C7EDC8_.js";
import "../../target-errors-C8xePsI5.js";
import "../../commands-registry-DJWLO-6B.js";
import "../../skill-commands-B6iXy7Nx.js";
import "../../fetch-CONQGbzL.js";
import "../../channel-activity-CVe33Aey.js";
import "../../tables-DushlpuO.js";
import "../../send-CHthYes-.js";
import "../../outbound-attachment-3soL6fn0.js";
import "../../send-DYCEGbmH.js";
import "../../proxy-BzwL4n0W.js";
import "../../manager-DS9FBMMG.js";
import "../../query-expansion-DUWWrH-g.js";
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
//#region src/gateway/boot.ts
function generateBootSessionId() {
	return `boot-${(/* @__PURE__ */ new Date()).toISOString().replace(/[:.]/g, "-").replace("T", "_").replace("Z", "")}-${crypto.randomUUID().slice(0, 8)}`;
}
const log$1 = createSubsystemLogger("gateway/boot");
const BOOT_FILENAME = "BOOT.md";
function buildBootPrompt(content) {
	return [
		"You are running a boot check. Follow BOOT.md instructions exactly.",
		"",
		"BOOT.md:",
		content,
		"",
		"If BOOT.md asks you to send a message, use the message tool (action=send with channel + target).",
		"Use the `target` field (not `to`) for message tool destinations.",
		`After sending with the message tool, reply with ONLY: ${SILENT_REPLY_TOKEN}.`,
		`If nothing needs attention, reply with ONLY: ${SILENT_REPLY_TOKEN}.`
	].join("\n");
}
async function loadBootFile(workspaceDir) {
	const bootPath = path.join(workspaceDir, BOOT_FILENAME);
	try {
		const trimmed = (await fs.readFile(bootPath, "utf-8")).trim();
		if (!trimmed) return { status: "empty" };
		return {
			status: "ok",
			content: trimmed
		};
	} catch (err) {
		if (err.code === "ENOENT") return { status: "missing" };
		throw err;
	}
}
function snapshotMainSessionMapping(params) {
	const agentId = resolveAgentIdFromSessionKey(params.sessionKey);
	const storePath = resolveStorePath(params.cfg.session?.store, { agentId });
	try {
		const entry = loadSessionStore(storePath, { skipCache: true })[params.sessionKey];
		if (!entry) return {
			storePath,
			sessionKey: params.sessionKey,
			canRestore: true,
			hadEntry: false
		};
		return {
			storePath,
			sessionKey: params.sessionKey,
			canRestore: true,
			hadEntry: true,
			entry: structuredClone(entry)
		};
	} catch (err) {
		log$1.debug("boot: could not snapshot main session mapping", {
			sessionKey: params.sessionKey,
			error: String(err)
		});
		return {
			storePath,
			sessionKey: params.sessionKey,
			canRestore: false,
			hadEntry: false
		};
	}
}
async function restoreMainSessionMapping(snapshot) {
	if (!snapshot.canRestore) return;
	try {
		await updateSessionStore(snapshot.storePath, (store) => {
			if (snapshot.hadEntry && snapshot.entry) {
				store[snapshot.sessionKey] = snapshot.entry;
				return;
			}
			delete store[snapshot.sessionKey];
		}, { activeSessionKey: snapshot.sessionKey });
		return;
	} catch (err) {
		return err instanceof Error ? err.message : String(err);
	}
}
async function runBootOnce(params) {
	const bootRuntime = {
		log: () => {},
		error: (message) => log$1.error(String(message)),
		exit: defaultRuntime.exit
	};
	let result;
	try {
		result = await loadBootFile(params.workspaceDir);
	} catch (err) {
		const message = err instanceof Error ? err.message : String(err);
		log$1.error(`boot: failed to read ${BOOT_FILENAME}: ${message}`);
		return {
			status: "failed",
			reason: message
		};
	}
	if (result.status === "missing" || result.status === "empty") return {
		status: "skipped",
		reason: result.status
	};
	const sessionKey = params.agentId ? resolveAgentMainSessionKey({
		cfg: params.cfg,
		agentId: params.agentId
	}) : resolveMainSessionKey(params.cfg);
	const message = buildBootPrompt(result.content ?? "");
	const sessionId = generateBootSessionId();
	const mappingSnapshot = snapshotMainSessionMapping({
		cfg: params.cfg,
		sessionKey
	});
	let agentFailure;
	try {
		await agentCommand({
			message,
			sessionKey,
			sessionId,
			deliver: false,
			senderIsOwner: true
		}, bootRuntime, params.deps);
	} catch (err) {
		agentFailure = err instanceof Error ? err.message : String(err);
		log$1.error(`boot: agent run failed: ${agentFailure}`);
	}
	const mappingRestoreFailure = await restoreMainSessionMapping(mappingSnapshot);
	if (mappingRestoreFailure) log$1.error(`boot: failed to restore main session mapping: ${mappingRestoreFailure}`);
	if (!agentFailure && !mappingRestoreFailure) return { status: "ran" };
	return {
		status: "failed",
		reason: [agentFailure ? `agent run failed: ${agentFailure}` : void 0, mappingRestoreFailure ? `mapping restore failed: ${mappingRestoreFailure}` : void 0].filter((part) => Boolean(part)).join("; ")
	};
}
//#endregion
//#region src/hooks/bundled/boot-md/handler.ts
const log = createSubsystemLogger("hooks/boot-md");
const runBootChecklist = async (event) => {
	if (!isGatewayStartupEvent(event)) return;
	if (!event.context.cfg) return;
	const cfg = event.context.cfg;
	const deps = event.context.deps ?? createDefaultDeps();
	const agentIds = listAgentIds(cfg);
	for (const agentId of agentIds) {
		const workspaceDir = resolveAgentWorkspaceDir(cfg, agentId);
		const result = await runBootOnce({
			cfg,
			deps,
			workspaceDir,
			agentId
		});
		if (result.status === "failed") {
			log.warn("boot-md failed for agent startup run", {
				agentId,
				workspaceDir,
				reason: result.reason
			});
			continue;
		}
		if (result.status === "skipped") log.debug("boot-md skipped for agent startup run", {
			agentId,
			workspaceDir,
			reason: result.reason
		});
	}
};
//#endregion
export { runBootChecklist as default };
