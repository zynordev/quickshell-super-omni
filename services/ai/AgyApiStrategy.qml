import QtQuick
import Quickshell
import qs.modules.common.functions as CF

ApiStrategy {
    property bool isThinking: false
    property string selectedModel: "gemini-4-argon-medium"
    property string latestPrompt: ""
    property string attachedFile: ""
    readonly property string runnerPath: CF.FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/ai/agy_runner.py"))

    function buildEndpoint(model: AiModel): string {
        return "agy://local";
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        selectedModel = model.model || "gemini-4-argon-medium";
        let lastUserMsg = "";
        for (let i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role === "user") {
                lastUserMsg = messages[i].rawContent || messages[i].content || "";
                break;
            }
        }
        latestPrompt = lastUserMsg;
        attachedFile = filePath || "";
        return {};
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    function finalizeScriptContent(scriptContent: string): string {
        const escModel = CF.StringUtils.shellSingleQuoteEscape(selectedModel);
        const escPrompt = CF.StringUtils.shellSingleQuoteEscape(latestPrompt);
        const escFile = CF.StringUtils.shellSingleQuoteEscape(attachedFile);
        return `#!/usr/bin/env bash\nexec python3 '${runnerPath}' run '${escModel}' '${escPrompt}' '${escFile}'\n`;
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        let cleanData = line.trim();
        if (!cleanData) return {};

        try {
            const ev = JSON.parse(cleanData);

            if (ev.event === "step_update" && ev.step_update) {
                const su = ev.step_update;
                if (su.step_type === "tool" && su.state === "ACTIVE") {
                    if (!isThinking) {
                        isThinking = true;
                        const startBlock = "<think>\n";
                        message.content += startBlock;
                        message.rawContent += startBlock;
                    }
                    let paramSummary = "";
                    const params = su.tool_info?.parameters;
                    if (params) {
                        paramSummary = params.CommandLine || params.Path || params.query || JSON.stringify(params);
                    }
                    const toolLine = `🔧 ${su.tool_name}${paramSummary ? ": " + paramSummary : ""}\n`;
                    message.content += toolLine;
                    message.rawContent += toolLine;
                } else if (su.step_type === "agent_response" && su.text_delta) {
                    if (isThinking) {
                        isThinking = false;
                        const endBlock = "</think>\n\n";
                        message.content += endBlock;
                        message.rawContent += endBlock;
                    }
                    message.content += su.text_delta;
                    message.rawContent += su.text_delta;
                }

                if (su.usage) {
                    return {
                        tokenUsage: {
                            input: su.usage.input_tokens ?? -1,
                            output: su.usage.output_tokens ?? -1,
                            total: su.usage.total_tokens ?? -1
                        }
                    };
                }
                return {};
            }

            if (ev.event === "result" && ev.result) {
                if (isThinking) {
                    isThinking = false;
                    const endBlock = "</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                if (message.content.trim().length === 0 && ev.result.response) {
                    message.content = ev.result.response;
                    message.rawContent = ev.result.response;
                }
                const out = { finished: true };
                if (ev.result.usage) {
                    out.tokenUsage = {
                        input: ev.result.usage.input_tokens ?? -1,
                        output: ev.result.usage.output_tokens ?? -1,
                        total: ev.result.usage.total_tokens ?? -1
                    };
                }
                return out;
            }
        } catch (e) {
            console.log("[AI/agy] Could not parse line:", e);
        }

        return {};
    }

    function onRequestFinished(message: AiMessageData) {
        if (isThinking) {
            isThinking = false;
            const endBlock = "</think>\n\n";
            message.content += endBlock;
            message.rawContent += endBlock;
        }
        return { finished: true };
    }

    function reset() {
        isThinking = false;
    }
}
