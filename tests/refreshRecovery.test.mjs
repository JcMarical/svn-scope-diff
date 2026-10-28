import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { transformWithOxc } from "vite";

async function loadModule(name) {
  const path = fileURLToPath(new URL(`../src/${name}.ts`, import.meta.url));
  const { code } = await transformWithOxc(await readFile(path, "utf8"), path);
  return import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
}
const { withReadTimeout } = await loadModule("readTimeout");
const { listenForDraftClose } = await loadModule("windowClose");

test("读取不返回时结束等待，迟到的旧结果不会覆盖新结果", async (context) => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  let complete;
  let loading = true;
  let result = "cached";
  const task = withReadTimeout(new Promise((resolve) => { complete = resolve; }), 120000, "读取超时")
    .then((value) => { result = value; }).finally(() => { loading = false; });
  const failure = assert.rejects(task, /读取超时/);
  context.mock.timers.tick(120000);
  await failure;
  assert.equal(loading, false);
  result = await withReadTimeout(Promise.resolve("fresh"), 120000, "读取超时");
  complete("stale");
  await Promise.resolve();
  assert.equal(result, "fresh");
});

test("正常读取和真实错误保留原结果，完成后不遗留超时", async (context) => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  assert.equal(await withReadTimeout(Promise.resolve(42), 10, "超时"), 42);
  const error = new Error("工作副本不可用");
  await assert.rejects(withReadTimeout(Promise.reject(error), 10, "超时"), (value) => value === error);
  context.mock.timers.tick(10);
});

test("无草稿的窗口不注册关闭拦截，不依赖扫描或前端销毁请求", () => {
  const cleanup = listenForDraftClose(false,
    () => { assert.fail("不应注册关闭事件"); },
    () => { assert.fail("不应询问放弃草稿"); },
    assert.fail);
  cleanup();
});

test("有草稿时取消关闭保留编辑，确认放弃才允许关闭", async () => {
  let handler;
  let allowDiscard = false;
  let prevented = 0;
  let removed = 0;
  const cleanup = listenForDraftClose(true,
    async (callback) => { handler = callback; return () => { removed += 1; }; },
    () => allowDiscard, assert.fail);
  await Promise.resolve();
  handler({ preventDefault() { prevented += 1; } });
  assert.equal(prevented, 1);
  allowDiscard = true;
  handler({ preventDefault() { prevented += 1; } });
  assert.equal(prevented, 1);
  cleanup();
  assert.equal(removed, 1);
});

test("保存或卸载发生在异步注册完成之前，也会移除迟到的关闭监听", async () => {
  let complete;
  let removed = 0;
  const cleanup = listenForDraftClose(true,
    () => new Promise((resolve) => { complete = resolve; }), () => false, assert.fail);
  cleanup();
  complete(() => { removed += 1; });
  await Promise.resolve();
  assert.equal(removed, 1);
});

test("关闭监听注册失败会报告错误", async () => {
  const error = new Error("通信失败");
  let reported;
  listenForDraftClose(true, async () => { throw error; }, () => false, (value) => { reported = value; });
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(reported, error);
});
