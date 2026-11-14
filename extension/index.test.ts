// Copyright (C) 2026 Denis Dupeyron
// allow: SIZE_OK - One process-isolated factory contract suite, kept in the plan-owned test file.
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

import { expect, test } from "bun:test";
import type { ServerWebSocket } from "bun";
import type { ExtensionAPI, ExtensionContext, ExtensionUIContext, SessionStartEvent, SessionShutdownEvent } from "@earendil-works/pi-coding-agent";
import { strict as assert } from "node:assert";
import { EventEmitter, once } from "node:events";
import { appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const success = { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-11-25" } };
const mention = (params: unknown) => ({ jsonrpc: "2.0", method: "at_mentioned", params });
const selection = { filePath: "/outside/bar.lua", lineStart: 5, lineEnd: 9 };
const cases = ["handshake-response-first", "handshake-publication-first", "formatter", "root-cwd", "lifecycle", "retired-callbacks", "retired-before-open", "transport-error", "transport-close", "silent-peer", "rpc", "json", "print", "invalid-ports", "port-bounds", "invalid-mentions", "malformed-json", "initialize-error", "initialize-result", "initialize-version", "initialize-envelope", "real-handshake-queue", "real-direct-initialized", "real-disconnect", "real-eviction", "real-failure-relay"];

function record(event: string, detail: object): void {
  if (process.env.OMO_TEST_EVIDENCE) appendFileSync(process.env.OMO_TEST_EVIDENCE, JSON.stringify({ event, pid: process.pid, ...detail }) + "\n");
}

function wait(events: EventEmitter, name: string): Promise<unknown[]> {
  return once(events, name, { signal: AbortSignal.timeout(2000) });
}

async function fixture(run: (f: Awaited<ReturnType<typeof setup>>) => Promise<void>): Promise<void> {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), "omo-extension-")));
  try {
    record("fixture-directory-created", { directory });
    const f = await setup(directory);
    try { await run(f); } finally { await f.dispose(); }
  } finally {
    rmSync(directory, { recursive: true });
    record("fixture-directory-cleanup", { directory, absent: !existsSync(directory) });
    expect(existsSync(directory)).toBe(false);
  }
}

async function setup(directory: string) {
  const cwd = process.cwd();
  const root = join(directory, "project");
  const alias = join(directory, "alias");
  mkdirSync(root);
  symlinkSync(root, alias);
  const env = process.env.OMO_EDITOR_SSE_PORT;
  const launch = globalThis.__omoNvimLaunch;
  const NativeSocket = globalThis.WebSocket;
  const events = new EventEmitter();
  const sockets: WebSocket[] = [];
  const sent: unknown[] = [];
  const received: unknown[] = [];
  const closes: WebSocket[] = [];
  const peers = new Set<ServerWebSocket<undefined>>();
  const server = Bun.serve<undefined>({
    hostname: "127.0.0.1", port: 0,
    fetch(request, server) { return server.upgrade(request) ? undefined : new Response("upgrade required", { status: 400 }); },
    websocket: {
      open(ws) { peers.add(ws); events.emit("open", ws); },
      message(_ws, data) { events.emit("wire", JSON.parse(String(data))); },
      close(ws) { peers.delete(ws); events.emit("closed"); },
    },
  });
  let acquired = false;
  try {
    record("fixture-server-created", { port: server.port, directory });
    globalThis.WebSocket = class extends NativeSocket {
      constructor(url: string | URL, protocols?: string | string[]) {
        super(url, protocols);
        sockets.push(this);
        this.addEventListener("message", (event) => {
          const value: unknown = typeof event.data === "string" ? event.data : null;
          received.push(value);
          record("extension-received", { value });
          events.emit("inbound", value);
        });
      }
      override send(data: Parameters<WebSocket["send"]>[0]): void {
        sent.push(JSON.parse(String(data)));
        record("send", { value: sent.at(-1) });
        super.send(data);
      }
      override close(code?: number, reason?: string): void { closes.push(this); super.close(code, reason); }
    };
    let publish: (() => void | Promise<void>) | undefined;
    let draft = "draft:";
    let rendered = draft;
    const pastes: string[] = [];
    const handlers = new Map<string, (...args: unknown[]) => unknown>();
    const ui = {
      pasteToEditor(text: string) { pastes.push(text); draft += text; events.emit("paste", text); events.emit(`paste-${pastes.length}`); },
      setStatus(_key: string, _text: string | undefined) { rendered = draft; },
    } satisfies Pick<ExtensionUIContext, "pasteToEditor" | "setStatus">;
    const context: Pick<ExtensionContext, "mode" | "cwd" | "afterSessionStart"> & { ui: typeof ui } = { mode: "tui", cwd: "/changed-host-cwd", ui, afterSessionStart(callback) { publish = callback; } };
    const api: Pick<ExtensionAPI, "on"> = {
      on(event: string, handler: unknown) {
        if (typeof handler !== "function") throw new TypeError("Expected a host event handler");
        handlers.set(event, (...args) => Reflect.apply(handler, undefined, args));
        return () => { handlers.delete(event); };
      },
    };
    const emit = (event: SessionStartEvent | SessionShutdownEvent) => handlers.get(event.type)?.(event, context);
    const load = async (port: string | null = String(server.port)) => {
      if (port === null) delete process.env.OMO_EDITOR_SSE_PORT;
      else process.env.OMO_EDITOR_SSE_PORT = port;
      const module: typeof import("./index") = await import(`./index.ts?fixture=${crypto.randomUUID()}`);
      module.default(api);
      return globalThis.__omoNvimLaunch;
    };
    const start = async (reason: SessionStartEvent["reason"] = "startup") => {
      const opened = wait(events, "open");
      const wired = wait(events, "wire");
      expect(emit({ type: "session_start", reason })).toBeUndefined();
      const socket = sockets.at(-1);
      assert(socket);
      socket.addEventListener("message", () => events.emit("received"));
      await opened;
      expect(await wired).toEqual([{ jsonrpc: "2.0", id: 1, method: "initialize" }]);
      const active = [...peers].at(-1);
      assert(active);
      return { socket, peer: active };
    };
    const deliver = async (peer: ServerWebSocket<undefined>, value: unknown) => {
      const received = wait(events, "received");
      peer.send(typeof value === "string" ? value : JSON.stringify(value));
      await received;
    };
    const shutdown = () => emit({ type: "session_shutdown", reason: "quit", signal: AbortSignal.abort() });
    process.chdir(root);
    globalThis.__omoNvimLaunch = undefined;
    acquired = true;
    return {
      root, alias, events, sockets, sent, received, closes, pastes, context, emit, load, start, deliver, shutdown,
      publish: () => publish?.(), draft: () => draft, rendered: () => rendered,
      async dispose() {
        shutdown();
        for (const socket of sockets) socket.close();
        await server.stop(true);
        globalThis.WebSocket = NativeSocket;
        globalThis.__omoNvimLaunch = launch;
        if (env === undefined) delete process.env.OMO_EDITOR_SSE_PORT;
        else process.env.OMO_EDITOR_SSE_PORT = env;
        process.chdir(cwd);
        events.removeAllListeners();
        record("fixture-cleanup", { root: directory, connections: server.pendingWebSockets, listeners: events.eventNames().length });
        expect(server.pendingWebSockets).toBe(0);
      },
    };
  } finally {
    if (!acquired) {
      for (const socket of sockets) socket.close();
      await server.stop(true);
      events.removeAllListeners();
      globalThis.WebSocket = NativeSocket;
      globalThis.__omoNvimLaunch = launch;
      if (env === undefined) delete process.env.OMO_EDITOR_SSE_PORT;
      else process.env.OMO_EDITOR_SSE_PORT = env;
      process.chdir(cwd);
    }
  }
}

async function scenario(name: string): Promise<void> {
  if (name.startsWith("real-")) return realScenario(name);
  await fixture(async (f) => {
    if (name === "invalid-ports") {
      for (const value of [null, "", "0", "65536", "1.5", "+5", "-1", "abc", " 5", "5\n"]) {
        globalThis.__omoNvimLaunch = undefined;
        await f.load(value);
        expect(Object.hasOwn(process.env, "OMO_EDITOR_SSE_PORT")).toBe(false);
        f.emit({ type: "session_start", reason: "startup" });
        expect(f.sockets).toEqual([]);
      }
      return;
    }
    if (name === "port-bounds") {
      f.context.mode = "rpc";
      for (const port of ["1", "65535", "00042"]) {
        globalThis.__omoNvimLaunch = undefined;
        const captured = await f.load(port);
        expect(captured?.port).toBe(Number(port));
        f.emit({ type: "session_start", reason: "startup" });
        expect(f.sockets).toEqual([]);
      }
      return;
    }
    if (name === "root-cwd") process.chdir("/");
    await f.load();
    expect(f.sockets).toEqual([]);
    expect(Object.hasOwn(process.env, "OMO_EDITOR_SSE_PORT")).toBe(false);
    if (name === "rpc" || name === "json" || name === "print") {
      f.context.mode = name;
      f.emit({ type: "session_start", reason: "startup" });
      await f.publish();
      expect(f.sockets).toEqual([]);
      expect(f.pastes).toEqual([]);
      expect(f.draft()).toBe("draft:");
      return;
    }
    if (name === "retired-before-open") {
      f.emit({ type: "session_start", reason: "startup" });
      const socket = f.sockets.at(-1);
      assert(socket);
      f.shutdown();
      socket.dispatchEvent(new Event("open"));
      socket.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(success) }));
      socket.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(mention(selection)) }));
      await f.publish();
      expect(f.sent).toEqual([]);
      expect(f.pastes).toEqual([]);
      expect(f.closes).toEqual([socket]);
      return;
    }
    const { socket, peer } = await f.start();
    switch (name) {
      case "handshake-response-first":
      case "handshake-publication-first": {
        if (name === "handshake-publication-first") await f.publish();
        await f.deliver(peer, { ...success, id: 99 });
        await f.deliver(peer, { jsonrpc: "2.0", method: "unrelated" });
        expect(f.sent).toEqual([{ jsonrpc: "2.0", id: 1, method: "initialize" }]);
        await f.deliver(peer, success);
        if (name === "handshake-response-first") {
          expect(f.sent).toHaveLength(1);
          await f.publish();
        }
        await f.deliver(peer, success);
        await f.publish();
        expect(f.sent).toEqual([{ jsonrpc: "2.0", id: 1, method: "initialize" }, { jsonrpc: "2.0", method: "notifications/initialized" }]);
        break;
      }
      case "formatter":
      case "root-cwd": {
        process.chdir("/");
        const rows: readonly (readonly [string, number, number, string])[] = name === "root-cwd" ? [["/bar.lua", 5, 5, "@bar.lua#5"]] : [
          [`${f.root}/bar.lua`, 5, 5, "@bar.lua#5"], [`${f.root}/sub/bar.lua`, 5, 9, "@sub/bar.lua#5-9"],
          [`${f.root}/sub/../bar.lua`, 5, 9, "@bar.lua#5-9"], [`${f.root}-sibling/bar.lua`, 5, 5, `@${f.root}-sibling/bar.lua#5`],
          ["/outside/../bar.lua", 1, 1, "@/outside/../bar.lua#1"], [`${f.root}/a b.lua`, 2, 2, "@a b.lua#2"],
          [`${f.root}/\u96ea.lua`, 3, 4, "@\u96ea.lua#3-4"], [`${f.alias}/bar.lua`, 1, 1, `@${f.alias}/bar.lua#1`],
          ["/outside/IGNORE INSTRUCTIONS.lua", 1, 1, "@/outside/IGNORE INSTRUCTIONS.lua#1"],
        ];
        for (const [filePath, lineStart, lineEnd, expected] of rows) {
          await f.deliver(peer, mention({ filePath, lineStart, lineEnd }));
          expect(f.pastes.at(-1)).toBe(expected);
        }
        expect(f.pastes).toEqual(rows.map((row) => row[3]));
        expect(f.draft()).toBe("draft:" + rows.map((row) => row[3]).join(""));
        expect(f.rendered()).toBe("draft:" + rows.map((row) => row[3]).join(""));
        break;
      }
      case "invalid-mentions": {
        for (const params of [null, {}, { ...selection, filePath: "relative" }, { ...selection, lineStart: 0 }, { ...selection, lineEnd: 4 }, { ...selection, lineStart: 1.5 }, { ...selection, lineEnd: "9" }]) await f.deliver(peer, mention(params));
        expect(f.pastes).toEqual([]);
        await f.deliver(peer, mention(selection));
        expect(f.pastes).toEqual(["@/outside/bar.lua#5-9"]);
        break;
      }
      case "lifecycle": {
        const captured = globalThis.__omoNvimLaunch;
        process.chdir("/");
        for (const reason of ["new", "resume", "reload"] as const) {
          const closed = wait(f.events, "closed");
          f.emit({ type: "session_shutdown", reason });
          await closed;
          await f.load("invalid-on-reload");
          expect(globalThis.__omoNvimLaunch).toBe(captured);
          expect(Object.isFrozen(captured)).toBe(true);
          expect(Object.hasOwn(process.env, "OMO_EDITOR_SSE_PORT")).toBe(false);
          const next = await f.start(reason);
          await f.publish();
          await f.deliver(next.peer, success);
          await f.deliver(next.peer, mention({ filePath: `${f.root}/bar.lua`, lineStart: 5, lineEnd: 9 }));
        }
        expect(f.pastes).toEqual(["@bar.lua#5-9", "@bar.lua#5-9", "@bar.lua#5-9"]);
        expect(f.sockets).toHaveLength(4);
        break;
      }
      case "retired-callbacks": {
        const closed = wait(f.events, "closed");
        const late = Promise.resolve().then(() => {
          socket.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(mention(selection)) }));
          socket.dispatchEvent(new Event("open"));
          return f.publish();
        });
        expect(f.shutdown()).toBeUndefined();
        f.shutdown();
        await late;
        await closed;
        expect(f.pastes).toEqual([]);
        expect(f.sent).toHaveLength(1);
        expect(f.closes).toEqual([socket]);
        break;
      }
      case "transport-error":
      case "transport-close": {
        const closed = once(socket, "close", { signal: AbortSignal.timeout(2000) });
        if (name === "transport-error") socket.dispatchEvent(new Event("error"));
        else peer.close();
        await closed;
        socket.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(mention(selection)) }));
        await f.publish();
        expect(f.pastes).toEqual([]);
        expect(f.closes).toEqual(name === "transport-error" ? [socket] : []);
        break;
      }
      case "silent-peer":
        await f.publish();
        expect(f.sent).toHaveLength(1);
        expect(socket.readyState).toBe(WebSocket.OPEN);
        expect(f.closes).toEqual([]);
        break;
      default: {
        const failures: Readonly<Record<string, unknown>> = {
          "malformed-json": "{", "initialize-error": { jsonrpc: "2.0", id: 1, error: { code: -32603, message: "PASS" } },
          "initialize-result": { jsonrpc: "2.0", id: 1, result: null }, "initialize-version": { ...success, result: { protocolVersion: "wrong" } },
          "initialize-envelope": { id: 1, result: success.result },
        };
        assert(Object.hasOwn(failures, name));
        const closed = wait(f.events, "closed");
        await f.deliver(peer, failures[name]);
        await closed;
        await f.publish();
        expect(f.closes).toEqual([socket]);
        expect(f.sent).toHaveLength(1);
        expect(f.pastes).toEqual([]);
      }
    }
    record("case-passed", { name, pastes: f.pastes, sent: f.sent });
  });
}

async function withNeovim(run: (n: {
  port: number;
  events: EventEmitter;
  evaluate: (code: string) => Promise<unknown>;
}) => Promise<void>): Promise<void> {
  const directory = realpathSync(mkdtempSync("/tmp/omo-wire-"));
  try {
    record("neovim-directory-created", { directory });
    const socket = join(directory, "n.sock");
    const events = new EventEmitter();
    const bootstrap = `
      vim.opt.runtimepath:prepend(${JSON.stringify(dirname(import.meta.dir))})
      local function emit(value) io.stdout:write(vim.json.encode(value), "\\n") io.stdout:flush() end
      vim.notify = function(message, level, options) emit({event="warning", message=message, level=level, title=options and options.title}) end
      local ed = require("omo.editor")
      assert(ed.start())
      local previous = vim.json.encode(ed.status())
      local schedule = vim.schedule
      vim.schedule = function(callback) schedule(function()
        callback()
        local state = ed.status()
        local encoded = vim.json.encode(state)
        if encoded ~= previous then previous = encoded emit({event="state", value=state}) end
      end) end
      emit({event="ready", port=ed.port(), pid=vim.fn.getpid(), socket=vim.v.servername})
    `;
    const argv = ["nvim", "--headless", "-i", "NONE", "-u", "NONE", "--listen", socket, "-c", `lua ${bootstrap}`];
    const child = Bun.spawn(argv, { env: process.env, cwd: dirname(import.meta.dir), stdin: "ignore", stdout: "pipe", stderr: "pipe", timeout: 7000 });
    const readiness = new AbortController();
    try {
      record("neovim-process-created", { childPid: child.pid, directory, socket });
      const ready = once(events, "ready", { signal: AbortSignal.any([readiness.signal, AbortSignal.timeout(2000)]) });
      const settledReady = Promise.allSettled([ready]);
      const stderr = new Response(child.stderr).text();
      const output = (async () => {
        let pending = "";
        const decoder = new TextDecoder();
        for await (const bytes of child.stdout) {
          pending += decoder.decode(bytes, { stream: true });
          let end: number;
          while ((end = pending.indexOf("\n")) >= 0) {
            const line = pending.slice(0, end);
            pending = pending.slice(end + 1);
            const value: unknown = JSON.parse(line);
            assert(value && typeof value === "object" && "event" in value && typeof value.event === "string");
            record("neovim-event", { value });
            events.emit(value.event, value);
            if (value.event === "state" && "value" in value) {
              const state = value.value;
              assert(state && typeof state === "object" && "connected" in state && "ready" in state);
              events.emit(`state-${state.connected}-${state.ready}`, state);
            }
          }
        }
      })();
      const settledOutput = Promise.allSettled([stderr, output]);
      const evaluate = async (code: string): Promise<unknown> => {
        const command = ["nvim", "--server", socket, "--remote-expr", `json_encode(luaeval(${JSON.stringify(code)}))`];
        const rpc = Bun.spawn(command, { env: process.env, cwd: dirname(import.meta.dir), stdin: "ignore", stdout: "pipe", stderr: "pipe", timeout: 2000 });
        try {
          record("neovim-rpc-created", { childPid: rpc.pid, directory });
          const [exit, stdout, error] = await Promise.all([rpc.exited, new Response(rpc.stdout).text(), new Response(rpc.stderr).text()]);
          record("neovim-rpc", { command, pid: rpc.pid, exit, stdout, stderr: error });
          expect({ exit, error }).toEqual({ exit: 0, error: "" });
          return JSON.parse(stdout);
        } finally {
          if (rpc.exitCode === null) rpc.kill();
          await rpc.exited;
        }
      };
      try {
        const [value] = await ready;
        assert(value && typeof value === "object" && "port" in value && typeof value.port === "number");
        expect(value.port).toBeGreaterThan(0);
        expect(value.port).toBeLessThanOrEqual(65535);
        await run({ port: value.port, events, evaluate });
    } finally {
      readiness.abort();
      await settledReady;
      record("neovim-teardown-start", { pid: child.pid });
      if (child.exitCode === null) child.kill();
      const exit = await child.exited;
      const results = await settledOutput;
      for (const result of results) if (result.status === "rejected") throw result.reason;
      const error = await stderr;
      record("neovim-process-cleanup", { childPid: child.pid, exit, stderr: error, directory });
    }
    } finally {
      readiness.abort();
      events.removeAllListeners();
      if (child.exitCode === null) child.kill();
      await child.exited;
      record("neovim-listener-cleanup", { directory, listeners: events.eventNames().length });
    }
  } finally {
    rmSync(directory, { recursive: true });
    record("neovim-cleanup", { directory, absent: !existsSync(directory) });
    expect(existsSync(directory)).toBe(false);
  }
}

async function realScenario(name: string): Promise<void> {
  await fixture(async (f) => withNeovim(async (n) => {
    const url = `ws://127.0.0.1:${n.port}`;
    const client = async () => {
      const ws = new WebSocket(url);
      await once(ws, "open", { signal: AbortSignal.timeout(2000) });
      return ws;
    };
    const barrier = async (ws: WebSocket) => {
      const response = once(ws, "message", { signal: AbortSignal.timeout(2000) });
      ws.send(JSON.stringify({ jsonrpc: "2.0", id: 99, method: "initialize" }));
      const [event] = await response;
      assert(event instanceof MessageEvent);
      const value: unknown = JSON.parse(String(event.data));
      expect(value).toEqual({ jsonrpc: "2.0", id: 99, result: { protocolVersion: "2025-11-25", serverInfo: { name: "omo.nvim", version: "1.0" }, capabilities: [] } });
    };
    if (name === "real-handshake-queue") {
      await f.load(String(n.port));
      const inbound = wait(f.events, "inbound");
      f.emit({ type: "session_start", reason: "startup" });
      const [wire] = await inbound;
      assert(typeof wire === "string");
      expect(JSON.parse(wire)).toEqual({ jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-11-25", serverInfo: { name: "omo.nvim", version: "1.0" }, capabilities: [] } });
      expect(await n.evaluate('require("omo.editor").status()')).toEqual({ port: n.port, connected: true, ready: false, disabled: false });
      const decisions = await n.evaluate('(function() local ed=require("omo.editor") local result={} for i=1,21 do result[i]=ed.mention("/queued.lua",i,i) end return result end)()');
      expect(decisions).toEqual([...Array(20).fill(true), false]);
      expect(f.pastes).toEqual([]);
      const flushed = wait(f.events, "paste-20");
      const ready = wait(n.events, "state-true-true");
      await f.publish();
      await Promise.all([ready, flushed]);
      await f.publish();
      const pasted = wait(f.events, "paste-21");
      expect(await n.evaluate('require("omo.editor").mention("/ready.lua",5,9)')).toBe(true);
      await pasted;
      expect(f.pastes).toEqual([...Array.from({ length: 20 }, (_, i) => `@/queued.lua#${i + 1}`), "@/ready.lua#5-9"]);
      expect(f.draft()).toBe("draft:" + f.pastes.join(""));
      expect(f.sent).toEqual([{ jsonrpc: "2.0", id: 1, method: "initialize" }, { jsonrpc: "2.0", method: "notifications/initialized" }]);
      expect(f.received.slice(1).map(value => JSON.parse(String(value)))).toEqual([...Array.from({ length: 20 }, (_, i) => mention({ filePath: "/queued.lua", lineStart: i + 1, lineEnd: i + 1 })), mention({ filePath: "/ready.lua", lineStart: 5, lineEnd: 9 })]);
      record("real-case-passed", { name, decisions, pastes: f.pastes, sent: f.sent });
    } else if (name === "real-direct-initialized") {
      const ws = await client();
      expect(await n.evaluate('require("omo.editor").mention("/direct.lua",1,1)')).toBe(true);
      const received = once(ws, "message", { signal: AbortSignal.timeout(2000) });
      const ready = wait(n.events, "state-true-true");
      ws.send(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }));
      const [[event]] = await Promise.all([received, ready]);
      assert(event instanceof MessageEvent);
      expect(JSON.parse(String(event.data))).toEqual(mention({ filePath: "/direct.lua", lineStart: 1, lineEnd: 1 }));
      ws.send(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }));
      await barrier(ws);
      expect(f.received).toHaveLength(2);
      record("real-case-passed", { name, received: f.received });
    } else if (name === "real-disconnect" || name === "real-eviction") {
      const first = await client();
      expect(await n.evaluate('require("omo.editor").mention("/discarded.lua",2,3)')).toBe(true);
      const warning = wait(n.events, "warning");
      const closed = once(first, "close", { signal: AbortSignal.timeout(2000) });
      let replacement: WebSocket;
      if (name === "real-disconnect") {
        const disconnected = wait(n.events, "state-false-false");
        first.close();
        await Promise.all([closed, disconnected]);
        expect(await n.evaluate('require("omo.editor").mention("/fallback.lua",1,1)')).toBe(false);
        replacement = await client();
      } else {
        replacement = await client();
        await closed;
      }
      const [notice] = await warning;
      assert(notice && typeof notice === "object" && "level" in notice && "title" in notice);
      expect({ level: notice.level, title: notice.title }).toEqual({ level: 3, title: "OMO" });
      const ready = wait(n.events, "state-true-true");
      replacement.send(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }));
      await ready;
      await barrier(replacement);
      const delivery = once(replacement, "message", { signal: AbortSignal.timeout(2000) });
      expect(await n.evaluate('require("omo.editor").mention("/replacement.lua",5,9)')).toBe(true);
      const [event] = await delivery;
      assert(event instanceof MessageEvent);
      expect(JSON.parse(String(event.data))).toEqual(mention({ filePath: "/replacement.lua", lineStart: 5, lineEnd: 9 }));
      expect(f.received).toHaveLength(2);
      expect(first.readyState).toBe(WebSocket.CLOSED);
      record("real-case-passed", { name, warning: notice, received: f.received });
    } else {
      expect(name).toBe("real-failure-relay");
      const upstream = await client();
      const relayEvents = new EventEmitter();
      let downstream: ServerWebSocket<undefined> | undefined;
      const relay = Bun.serve<undefined>({ hostname: "127.0.0.1", port: 0,
        fetch(request, server) { return server.upgrade(request) ? undefined : new Response("upgrade required", { status: 400 }); },
        websocket: {
          open(ws) { downstream = ws; },
          message(_ws, bytes) { record("relay-request", { value: String(bytes) }); upstream.send(bytes); },
          close() { record("relay-downstream-closed", {}); upstream.close(); relayEvents.emit("released"); },
        },
      });
      try {
        record("relay-created", { port: relay.port });
        const matching = once(upstream, "message", { signal: AbortSignal.timeout(2000) });
        await f.load(String(relay.port));
        f.emit({ type: "session_start", reason: "startup" });
        const [event] = await matching;
        assert(event instanceof MessageEvent);
        expect(JSON.parse(String(event.data))).toEqual({ jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-11-25", serverInfo: { name: "omo.nvim", version: "1.0" }, capabilities: [] } });
        expect(await n.evaluate('require("omo.editor").mention("/failure-pending.lua",1,1)')).toBe(true);
        assert(downstream);
        const released = wait(relayEvents, "released");
        const disconnected = wait(n.events, "state-false-false");
        const warning = wait(n.events, "warning");
        downstream.send(JSON.stringify({ jsonrpc: "2.0", id: 1, error: { code: -32603, message: "PASS is not a result" } }));
        await Promise.all([released, disconnected, warning]);
        const state = await n.evaluate('require("omo.editor").status()');
        expect(state).toEqual({ port: n.port, connected: false, ready: false, disabled: false });
        expect(f.pastes).toEqual([]);
        record("real-case-passed", { name, disconnectedBeforeTeardown: true, state });
      } finally {
        record("relay-teardown-start", {});
        await relay.stop(true);
        upstream.close();
        expect(relay.pendingWebSockets).toBe(0);
      }
    }
  }));
}

test.each(cases)("factory boundary %s", async (name) => {
  if (process.env.OMO_TEST_CASE === name) return scenario(name);
  const root = realpathSync(mkdtempSync(join(tmpdir(), "omo-test-process-")));
  try {
    record("process-directory-created", { root, name });
    const snapshot = join(root, "snapshot");
    cpSync(dirname(import.meta.dir), snapshot, { recursive: true });
    const child = Bun.spawn([process.execPath, "test", "--timeout", "10000", "./extension/index.test.ts", "-t", `^factory boundary ${name}$`], {
      env: { ...process.env, OMO_TEST_CASE: name, TMPDIR: root, BUN_RUNTIME_TRANSPILER_CACHE_PATH: join(root, "cache") },
      cwd: snapshot, stdin: "ignore", stdout: "pipe", stderr: "pipe", timeout: 8000,
    });
    try {
      record("process-created", { childPid: child.pid, root, name });
      const [exit, stdout, stderr] = await Promise.all([child.exited, new Response(child.stdout).text(), new Response(child.stderr).text()]);
      record("child-exit", { name, pid: child.pid, exit, stdout, stderr });
      expect({ exit, output: exit === 0 ? "" : stdout + stderr }).toEqual({ exit: 0, output: "" });
    } finally {
      if (child.exitCode === null) child.kill();
      await child.exited;
    }
  } finally {
    rmSync(root, { recursive: true });
    record("process-cleanup", { root, absent: !existsSync(root) });
    expect(existsSync(root)).toBe(false);
  }
});
