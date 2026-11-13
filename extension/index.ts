// Copyright (C) 2026 Denis Dupeyron
//
// This program is free software. You can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY. Without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isAbsolute, normalize, sep } from "node:path";

const suppliedPort = process.env.OMO_EDITOR_SSE_PORT;
delete process.env.OMO_EDITOR_SSE_PORT;

declare global {
  var __omoNvimLaunch: Readonly<{ port: number | undefined; cwd: string }> | undefined;
}

const parsedPort = suppliedPort && !/[^0-9]/.test(suppliedPort) ? Number(suppliedPort) : undefined;
globalThis.__omoNvimLaunch ??= Object.freeze({
  port: parsedPort && Number.isInteger(parsedPort) && parsedPort <= 65535 ? parsedPort : undefined,
  cwd: process.cwd(),
});
const launch = globalThis.__omoNvimLaunch;

export default function (pi: Pick<ExtensionAPI, "on">): void {
  let close: (() => void) | undefined;

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui" || launch.port === undefined) return;

    const ws = new WebSocket(`ws://127.0.0.1:${launch.port}`);
    let retired = false;
    let published = false;
    let initialized = false;
    let ready = false;

    const retire = (): void => {
      retired = true;
      ws.removeEventListener("message", message);
      ws.removeEventListener("open", open);
      ws.removeEventListener("error", fail);
      ws.removeEventListener("close", retire);
    };
    const fail = (): void => {
      if (retired) return;
      retire();
      ws.close();
    };
    const publish = (): void => {
      if (retired || ready || !published || !initialized) return;
      ready = true;
      ws.send(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }));
    };
    const open = (): void => {
      if (retired) return;
      ws.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize" }));
    };
    const message = (event: MessageEvent): void => {
      if (retired || typeof event.data !== "string") return;
      let rpc: unknown;
      try {
        rpc = JSON.parse(event.data);
      } catch (error) {
        if (!(error instanceof SyntaxError)) throw error;
        fail();
        return;
      }
      if (!rpc || typeof rpc !== "object") return;
      if ("id" in rpc && rpc.id === 1) {
        if (
          !("jsonrpc" in rpc) || rpc.jsonrpc !== "2.0" || "error" in rpc ||
          !("result" in rpc) || !rpc.result || typeof rpc.result !== "object" ||
          !("protocolVersion" in rpc.result) || rpc.result.protocolVersion !== "2025-11-25"
        ) {
          fail();
          return;
        }
        initialized = true;
        publish();
        return;
      }
      if (!("jsonrpc" in rpc) || rpc.jsonrpc !== "2.0" || !("method" in rpc) ||
          rpc.method !== "at_mentioned" || !("params" in rpc)) return;
      const p = rpc.params;
      if (!p || typeof p !== "object" || !("filePath" in p) || !("lineStart" in p) || !("lineEnd" in p)) return;
      if (typeof p.filePath !== "string" || !isAbsolute(p.filePath) ||
          typeof p.lineStart !== "number" || typeof p.lineEnd !== "number" ||
          !Number.isInteger(p.lineStart) || !Number.isInteger(p.lineEnd) ||
          p.lineStart < 1 || p.lineEnd < p.lineStart) return;
      const base = normalize(launch.cwd);
      const prefix = base.endsWith(sep) ? base : `${base}${sep}`;
      const target = normalize(p.filePath);
      const path = target.startsWith(prefix) ? target.slice(prefix.length) : p.filePath;
      ctx.ui.pasteToEditor(`@${path}#${p.lineStart}${p.lineEnd === p.lineStart ? "" : `-${p.lineEnd}`}`);
    };

    close = fail;
    ws.addEventListener("open", open);
    ws.addEventListener("message", message);
    ws.addEventListener("error", fail);
    ws.addEventListener("close", retire);
    const publication = (): void => {
      if (retired) return;
      published = true;
      publish();
    };
    if (ctx.afterSessionStart) ctx.afterSessionStart(publication);
    else publication();
  });

  pi.on("session_shutdown", () => close?.());
}
