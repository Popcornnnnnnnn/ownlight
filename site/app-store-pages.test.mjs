import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

async function readPage(path) {
  return readFile(new URL(path, import.meta.url), "utf8");
}

test("english privacy policy covers v1 App Store disclosure basics", async () => {
  const html = await readPage("./privacy/en/index.html");

  for (const requiredText of [
    "Ownlight Privacy Policy",
    "No account",
    "No tracking",
    "Local-first storage",
    "Data we handle",
    "How data is collected",
    "How data is used",
    "Data sharing",
    "Optional AI",
    "Bring your own provider",
    "Withdraw consent",
    "Retention",
    "iCloud Sync",
    "Export",
    "Delete your data",
    "Contact"
  ]) {
    assert.match(html, new RegExp(requiredText, "i"));
  }
});

test("simplified Chinese privacy policy covers v1 App Store disclosure basics", async () => {
  const html = await readPage("./privacy/zh-Hans/index.html");

  for (const requiredText of [
    "Ownlight 隐私政策",
    "无需账号",
    "无跟踪",
    "本地优先存储",
    "我们处理的数据",
    "数据如何收集",
    "数据如何使用",
    "数据共享边界",
    "可选 AI",
    "自带服务提供方",
    "撤回同意",
    "保留期限",
    "iCloud Sync",
    "导出",
    "删除你的数据",
    "联系方式"
  ]) {
    assert.match(html, new RegExp(requiredText, "i"));
  }
});

test("privacy root links to localized privacy policies", async () => {
  const html = await readPage("./privacy/index.html");

  assert.ok(html.includes('href="./zh-Hans/'));
  assert.ok(html.includes('href="./en/'));
  assert.match(html, /简体中文/);
  assert.match(html, /English/);
});

test("support page provides a real contact path and core help topics", async () => {
  const html = await readPage("./support/index.html");

  for (const requiredText of [
    "Ownlight Support",
    "Contact",
    "developer directly",
    "开发者本人维护",
    "API keys",
    "privacy",
    "AI",
    "iCloud",
    "export"
  ]) {
    assert.match(html, new RegExp(requiredText, "i"));
  }

  assert.match(html, /mailto:/i);
});
