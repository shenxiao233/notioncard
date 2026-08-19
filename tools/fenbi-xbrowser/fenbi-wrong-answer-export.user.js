// ==UserScript==
// @name         粉笔错题导出器
// @namespace    kncard-app
// @version      0.3.2
// @description  在粉笔题库页面捕获题目、答案和解析，并导出错题
// @match        https://tiku.fenbi.com/*
// @match        https://*.fenbi.com/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  const MESSAGE_SOURCE = 'kncard-fenbi-exporter';
  const TARGET_PATHS = ['/combine/static/solution', '/combine/exercise/getSolution'];
  const state = {
    questionsByKey: new Map(),
    questionsById: new Map(),
    answersByKey: new Map(),
    answersById: new Map(),
    seenUrls: new Set(),
    questionUrlTemplates: new Set(),
    answerUrlTemplates: new Set(),
    fetchedQuestionUrls: new Set(),
    fetchingKeys: new Set(),
    nextAnswerOrder: 0,
    nextFallbackOrder: 0,
    hydrating: false,
    requestCount: 0,
  };

  function isTargetUrl(rawUrl) {
    try {
      const url = new URL(rawUrl, location.href);
      return TARGET_PATHS.some((path) => url.pathname.includes(path));
    } catch (_) {
      return false;
    }
  }

  function targetKind(rawUrl) {
    try {
      const path = new URL(rawUrl, location.href).pathname;
      return path.includes('/combine/static/solution') ? 'question' : 'answer';
    } catch (_) {
      return 'unknown';
    }
  }

  function rememberRequestUrl(rawUrl) {
    if (!isTargetUrl(rawUrl)) return;
    if (targetKind(rawUrl) === 'question') state.questionUrlTemplates.add(rawUrl);
    if (targetKind(rawUrl) === 'answer') state.answerUrlTemplates.add(rawUrl);
  }

  function sendCaptured(url, text) {
    window.postMessage({
      source: MESSAGE_SOURCE,
      type: 'response',
      url,
      body: text,
    }, '*');
  }

  // This hook runs in page context so it can see the site's native fetch/XHR.
  function installPageHook() {
    if (window.__kncardFenbiHookInstalled) return;
    window.__kncardFenbiHookInstalled = true;

    const isPageTargetUrl = (rawUrl) => {
      try {
        const url = new URL(rawUrl, location.href);
        return url.pathname.includes('/combine/static/solution')
          || url.pathname.includes('/combine/exercise/getSolution');
      } catch (_) {
        return false;
      }
    };
    let nextRequestOrder = 0;
    const sendPageResponse = (url, body, requestOrder) => {
      window.postMessage({
        source: 'kncard-fenbi-exporter',
        type: 'response',
        url,
        body,
        requestOrder,
      }, '*');
    };

    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function (...args) {
        const requestUrl = typeof args[0] === 'string'
          ? args[0]
          : (args[0] && args[0].url) || '';
        const requestOrder = isPageTargetUrl(requestUrl) ? nextRequestOrder++ : null;
        const promise = originalFetch.apply(this, args);
        if (!isPageTargetUrl(requestUrl)) return promise;
        return promise.then((response) => {
          try {
            response.clone().text().then((body) => sendPageResponse(
              new URL(requestUrl, location.href).href,
              body,
              requestOrder,
            )).catch(() => {});
          } catch (_) {}
          return response;
        });
      };
    }

    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url, ...rest) {
      this.__kncardFenbiUrl = new URL(url, location.href).href;
      return originalOpen.call(this, method, url, ...rest);
    };
    XMLHttpRequest.prototype.send = function (...args) {
      const xhr = this;
      if (isPageTargetUrl(xhr.__kncardFenbiUrl)) {
        const requestOrder = nextRequestOrder++;
        xhr.__kncardFenbiRequestOrder = requestOrder;
        xhr.addEventListener('load', function () {
          let body = '';
          try { body = xhr.responseText || ''; } catch (_) {}
          if (!body) {
            try {
              body = typeof xhr.response === 'string'
                ? xhr.response
                : JSON.stringify(xhr.response);
            } catch (_) {}
          }
          if (body) sendPageResponse(xhr.__kncardFenbiUrl, body, requestOrder);
        });
      }
      return originalSend.apply(this, args);
    };
  }

  function injectPageHook() {
    const run = () => {
      try {
        const script = document.createElement('script');
        script.textContent = `(${installPageHook.toString()})();`;
        (document.documentElement || document.head || document.body).appendChild(script);
        script.remove();
      } catch (_) {
        // Some browsers block inline page-context injection through CSP.
        // The direct call is a useful fallback for userscript engines that
        // expose the page's window to the script.
        try { installPageHook(); } catch (_) {}
      }
    };
    if (document.documentElement) run();
    else setTimeout(run, 0);
  }

  function parseBody(body) {
    if (typeof body !== 'string') return body;
    const text = body.replace(/^\uFEFF/, '').trim();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch (_) {}

    // A few endpoints may return JSONP or JSON embedded in a <pre> element.
    const jsonp = text.match(/^[^(]+\((\{[\s\S]*\}|\[[\s\S]*\])\)\s*;?$/);
    if (jsonp) {
      try { return JSON.parse(jsonp[1]); } catch (_) {}
    }
    try {
      const doc = new DOMParser().parseFromString(text, 'text/html');
      const pre = doc.querySelector('pre');
      if (pre) return JSON.parse(pre.textContent.trim());
    } catch (_) {}
    return null;
  }

  function looksLikeQuestion(value) {
    return value && typeof value === 'object'
      && typeof value.content === 'string'
      && (Array.isArray(value.accessories) || value.correctAnswer);
  }

  function looksLikeAnswer(value) {
    return value && typeof value === 'object'
      && value.answer && typeof value.answer === 'object'
      && (value.key != null || value.id != null);
  }

  function finiteNumber(value) {
    if (value == null || value === '' || typeof value === 'boolean') return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  }

  function captureOrder(requestOrder, itemOrder) {
    const request = finiteNumber(requestOrder);
    if (request != null) return { request, item: itemOrder };
    return { request: Number.MAX_SAFE_INTEGER, item: state.nextFallbackOrder++ };
  }

  function walk(value, visit, fallbackKey) {
    if (!value || typeof value !== 'object') return;
    visit(value, fallbackKey);
    if (Array.isArray(value)) {
      value.forEach((item) => walk(item, visit, undefined));
      return;
    }
    Object.entries(value).forEach(([key, child]) => {
      walk(child, visit, key);
    });
  }

  function addQuestion(question, captureOrderValue) {
    const copy = { ...question };
    const key = String(copy.globalId || copy.key || '');
    const id = copy.id == null ? '' : String(copy.id);
    const previous = (key && state.questionsByKey.get(key))
      || (id && state.questionsById.get(id));
    if (copy.__captureOrder == null) {
      copy.__captureOrder = previous && previous.__captureOrder
        ? previous.__captureOrder
        : (captureOrderValue || captureOrder(null, 0));
    }
    if (key) state.questionsByKey.set(key, copy);
    if (id) state.questionsById.set(id, copy);
  }

  function addAnswer(answer, fallbackKey, captureOrderValue) {
    const copy = { ...answer };
    const key = String(copy.key || fallbackKey || '');
    const id = copy.id == null ? '' : String(copy.id);
    const previous = (key && state.answersByKey.get(key))
      || (id && state.answersById.get(id));
    if (key && !copy.key) copy.key = key;
    if (copy.__captureOrder == null) {
      copy.__captureOrder = previous && previous.__captureOrder
        ? previous.__captureOrder
        : (captureOrderValue || captureOrder(null, 0));
    }
    if (copy.__order == null) {
      copy.__order = previous && previous.__order != null
        ? previous.__order
        : state.nextAnswerOrder++;
    }
    if (key) state.answersByKey.set(key, copy);
    if (id) state.answersById.set(id, copy);
  }

  function ingest(url, body, requestOrder) {
    rememberRequestUrl(url);
    const parsed = parseBody(body);
    if (!parsed) return { questions: 0, answers: 0 };
    const kind = targetKind(url);
    let questions = 0;
    let answers = 0;
    let itemOrder = 0;
    walk(parsed, (value, fallbackKey) => {
      if (kind === 'question' && looksLikeQuestion(value)) {
        addQuestion(value, captureOrder(requestOrder, itemOrder++));
        questions += 1;
      }
      if (kind === 'answer' && looksLikeAnswer(value)) {
        addAnswer(value, fallbackKey, captureOrder(requestOrder, itemOrder++));
        answers += 1;
      }
    });
    state.seenUrls.add(url);
    state.requestCount += 1;
    updatePanel();
    return { questions, answers };
  }

  function findAnswer(question) {
    const key = String(question.globalId || question.key || '');
    const id = question.id == null ? '' : String(question.id);
    return (key && state.answersByKey.get(key))
      || (id && state.answersById.get(id))
      || null;
  }

  function allQuestions() {
    const values = [...state.questionsByKey.values(), ...state.questionsById.values()];
    const seen = new Set();
    return values.filter((question) => {
      const identity = String(question.globalId || question.key || question.id);
      if (seen.has(identity)) return false;
      seen.add(identity);
      return true;
    });
  }

  function allAnswers() {
    const values = [...state.answersByKey.values(), ...state.answersById.values()];
    const seen = new Set();
    return values.filter((answer) => {
      const identity = String(answer.key || answer.id || answer.__order);
      if (seen.has(identity)) return false;
      seen.add(identity);
      return true;
    });
  }

  function questionIdentity(question) {
    return String(question.globalId || question.key || question.id || '');
  }

  function answerIdentity(answer) {
    return String(answer && (answer.key || answer.id || answer.__order) || '');
  }

  function findQuestion(answer) {
    const key = String(answer && answer.key || '');
    const id = answer && answer.id == null ? '' : String(answer && answer.id || '');
    return (key && state.questionsByKey.get(key))
      || (id && state.questionsById.get(id))
      || null;
  }

  function isWrong(question, answer) {
    if (!answer) return false;
    if (answer.status === -1 || Number(answer.scoreRate) === 0) return true;
    if (answer.status === 1 || Number(answer.scoreRate) === 1) return false;
    const expected = question.correctAnswer && question.correctAnswer.choice;
    const actual = answer.answer && answer.answer.choice;
    return expected != null && actual != null && String(expected) !== String(actual);
  }

  function chineseNumberToArabic(value) {
    const text = String(value || '')
      .replace(/[０-９]/g, (char) => String.fromCharCode(char.charCodeAt(0) - 0xfee0));
    if (/^\d+$/.test(text)) return Number(text);
    const digits = { 零: 0, 〇: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
    const units = { 十: 10, 百: 100, 千: 1000, 万: 10000, 亿: 100000000 };
    let total = 0;
    let section = 0;
    let number = 0;
    for (const char of text) {
      if (Object.prototype.hasOwnProperty.call(digits, char)) {
        number = digits[char];
      } else if (Object.prototype.hasOwnProperty.call(units, char)) {
        const unit = units[char];
        if (unit < 10000) {
          section += (number || 1) * unit;
        } else {
          section = (section + number) * unit;
          total += section;
          section = 0;
        }
        number = 0;
      }
    }
    return total + section + number;
  }

  function sourceText(question) {
    return stripHtml(question && question.source || '').replace(/\s+/g, ' ').trim();
  }

  function sourceQuestionNumber(question) {
    const source = sourceText(question);
    const matches = [...source.matchAll(/第\s*([0-9０-９零〇一二三四五六七八九十百千万亿两]+)\s*题/gi)];
    if (!matches.length) return null;
    const number = chineseNumberToArabic(matches[matches.length - 1][1]);
    return Number.isFinite(number) ? number : null;
  }

  function rowCaptureOrder(row) {
    return (row.user && row.user.__captureOrder)
      || (row.question && row.question.__captureOrder)
      || null;
  }

  // Compare the question number globally. The paper name is deliberately not
  // part of this comparison: 第63题 must come before 第82题 regardless of
  // whether they belong to 吉林卷、湖南卷 or another paper.
  function compareRows(a, b) {
    const aNumber = sourceQuestionNumber(a.question);
    const bNumber = sourceQuestionNumber(b.question);
    if (aNumber != null && bNumber == null) return -1;
    if (aNumber == null && bNumber != null) return 1;
    if (aNumber != null && bNumber != null && aNumber !== bNumber) {
      return aNumber - bNumber;
    }

    const aCapture = rowCaptureOrder(a);
    const bCapture = rowCaptureOrder(b);
    if (aCapture && bCapture) {
      if (aCapture.request !== bCapture.request) return aCapture.request - bCapture.request;
      if (aCapture.item !== bCapture.item) return aCapture.item - bCapture.item;
    } else if (aCapture || bCapture) {
      return aCapture ? -1 : 1;
    }

    const aId = finiteNumber(a.question && a.question.id);
    const bId = finiteNumber(b.question && b.question.id);
    if (aId != null && bId != null && aId !== bId) return aId - bId;
    return 0;
  }

  function rows(includeAll) {
    const result = [];
    const matchedAnswers = new Set();

    allQuestions().forEach((question) => {
      const user = findAnswer(question);
      if (user) matchedAnswers.add(answerIdentity(user));
      if (includeAll || isWrong(question, user)) result.push({ question, user });
    });

    // Keep answers whose question detail has not been loaded yet. This makes
    // the export count complete instead of silently dropping those records.
    allAnswers().forEach((user) => {
      if (matchedAnswers.has(answerIdentity(user))) return;
      const question = findQuestion(user) || {
        id: user.id,
        globalId: user.key,
        source: '（题目详情未获取）',
        content: `题目详情未获取。题目 key：${user.key || '未知'}，id：${user.id || '未知'}`,
        accessories: [],
        solution: '',
        keypoints: [],
      };
      if (includeAll || isWrong(question, user)) result.push({ question, user, missing: !findQuestion(user) });
    });

    return result.sort(compareRows);
  }

  function choiceText(choice, options) {
    if (choice == null || choice === '') return '未作答';
    const index = Number(choice);
    const letter = Number.isInteger(index) && index >= 0 ? String.fromCharCode(65 + index) : String(choice);
    const text = Array.isArray(options) && options[index] != null ? `：${stripHtml(options[index])}` : '';
    return `${letter}${text}`;
  }

  function getOptions(question) {
    const accessory = (question.accessories || []).find((item) => Array.isArray(item.options));
    return accessory ? accessory.options : [];
  }

  function toAccessibleUrl(rawUrl) {
    const value = String(rawUrl || '').trim();
    if (!value || /^(data:|blob:|mailto:|tel:|javascript:|#)/i.test(value)) return value;
    if (value.startsWith('//')) return `https:${value}`;
    try {
      return new URL(value, location.href).href;
    } catch (_) {
      return value;
    }
  }

  function normalizeDocumentUrls(doc) {
    doc.querySelectorAll('[src], [href]').forEach((node) => {
      ['src', 'href'].forEach((attributeName) => {
        if (!node.hasAttribute(attributeName)) return;
        const value = node.getAttribute(attributeName);
        if (/^javascript:/i.test(String(value || '').trim())) return;
        node.setAttribute(attributeName, toAccessibleUrl(value));
      });
    });
    doc.querySelectorAll('[srcset]').forEach((node) => {
      const srcset = node.getAttribute('srcset') || '';
      const normalized = srcset.split(',').map((part) => {
        const pieces = part.trim().split(/\s+/);
        if (pieces[0]) pieces[0] = toAccessibleUrl(pieces[0]);
        return pieces.join(' ');
      }).join(', ');
      node.setAttribute('srcset', normalized);
    });
    return doc;
  }

  function normalizeHtml(value) {
    const doc = new DOMParser().parseFromString(String(value || ''), 'text/html');
    normalizeDocumentUrls(doc);
    return doc.body.innerHTML;
  }

  function stripHtml(value) {
    const doc = new DOMParser().parseFromString(String(value || ''), 'text/html');
    return (doc.body.textContent || '').replace(/\s+/g, ' ').trim();
  }

  function richTextToMarkdown(value) {
    const doc = new DOMParser().parseFromString(String(value || ''), 'text/html');
    normalizeDocumentUrls(doc);
    doc.querySelectorAll('img').forEach((image) => {
      const src = image.getAttribute('src');
      if (!src) return;
      image.replaceWith(doc.createTextNode(`![${image.getAttribute('alt') || '图片'}](${src})`));
    });
    doc.querySelectorAll('br').forEach((node) => node.replaceWith(doc.createTextNode('\n')));
    doc.querySelectorAll('p').forEach((node) => node.insertAdjacentText('afterend', '\n'));
    return (doc.body.textContent || '')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  function safeHtml(value) {
    const doc = new DOMParser().parseFromString(String(value || ''), 'text/html');
    normalizeDocumentUrls(doc);
    doc.querySelectorAll('script,style,iframe,object,embed,form').forEach((node) => node.remove());
    doc.querySelectorAll('*').forEach((node) => {
      [...node.attributes].forEach((attribute) => {
        if (/^on/i.test(attribute.name)) node.removeAttribute(attribute.name);
        if (/^(href|src)$/i.test(attribute.name) && /^javascript:/i.test(attribute.value.trim())) {
          node.removeAttribute(attribute.name);
        }
      });
    });
    return doc.body.innerHTML;
  }

  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function exportJson(includeAll) {
    const data = rows(includeAll).map(({ question, user, missing }, index) => ({
      sequence: index + 1,
      id: question.id,
      key: question.globalId || question.key || null,
      questionNumber: sourceQuestionNumber(question),
      originalOrder: user && user.__order != null ? user.__order + 1 : index + 1,
      questionLoaded: !missing,
      source: question.source || '',
      content: normalizeHtml(question.content || ''),
      options: getOptions(question).map(normalizeHtml),
      correctAnswer: question.correctAnswer || null,
      userAnswer: user ? user.answer || null : null,
      status: user ? user.status : null,
      scoreRate: user ? user.scoreRate : null,
      time: user ? user.time : null,
      solution: normalizeHtml(question.solution || ''),
      keypoints: (question.keypoints || []).map((item) => item.name || item),
    }));
    downloadFile(`fenbi-wrong-${dateStamp()}.json`, JSON.stringify({ exportedAt: new Date().toISOString(), data }, null, 2), 'application/json');
  }

  function exportMarkdown(includeAll) {
    const list = rows(includeAll);
    const markdown = list.map(({ question, user }, index) => {
      const options = getOptions(question);
      const optionLines = options.map((option, optionIndex) => `${String.fromCharCode(65 + optionIndex)}. ${richTextToMarkdown(option)}`).join('\n');
      const correct = question.correctAnswer && question.correctAnswer.choice;
      const actual = user && user.answer && user.answer.choice;
      const topics = (question.keypoints || []).map((item) => item.name || item).join('、');
      return `## ${index + 1}. ${stripHtml(question.source || '')}\n\n${richTextToMarkdown(question.content)}\n\n${optionLines}\n\n- 我的答案：${choiceText(actual, options)}\n- 正确答案：${choiceText(correct, options)}\n- 结果：${user && isWrong(question, user) ? '错误' : (user ? '正确' : '未匹配')}\n- 知识点：${topics || '无'}\n\n### 解析\n\n${richTextToMarkdown(question.solution)}\n`;
    }).join('\n---\n\n');
    downloadFile(`fenbi-wrong-${dateStamp()}.md`, `# 粉笔错题\n\n${markdown}`, 'text/plain;charset=utf-8');
  }

  function exportHtml(includeAll) {
    const list = rows(includeAll);
    const articles = list.map(({ question, user }, index) => {
      const options = getOptions(question);
      // <ol type="A"> 会自动显示 A/B/C/D；这里不再手动拼接字母，避免出现 AA、BB 等重复。
      const optionHtml = options.map((option) => `<li>${safeHtml(option)}</li>`).join('');
      const correct = question.correctAnswer && question.correctAnswer.choice;
      const actual = user && user.answer && user.answer.choice;
      return `<article><h2>${index + 1}. ${safeHtml(question.source || '')}</h2><div>${safeHtml(question.content)}</div><ol type="A">${optionHtml}</ol><p><b>我的答案：</b>${escapeHtml(choiceText(actual, options))}<br><b>正确答案：</b>${escapeHtml(choiceText(correct, options))}<br><b>结果：</b>${user && isWrong(question, user) ? '错误' : (user ? '正确' : '未匹配')}</p><h3>解析</h3><div>${safeHtml(question.solution)}</div></article>`;
    }).join('\n');
    const html = `<!doctype html><meta charset="utf-8"><title>粉笔错题</title><style>body{font-family:system-ui,-apple-system,"Noto Sans SC",sans-serif;line-height:1.7;max-width:900px;margin:0 auto;padding:16px;color:#222}article{border-bottom:1px solid #ddd;padding:12px 0 24px}img{max-width:100%;height:auto}li{margin:6px 0}</style><h1>粉笔错题</h1>${articles}`;
    downloadFile(`fenbi-wrong-${dateStamp()}.html`, html, 'text/html;charset=utf-8');
  }

  function dateStamp() {
    return new Date().toISOString().slice(0, 19).replace(/[T:]/g, '-');
  }

  function downloadFile(filename, content, mime) {
    const isMarkdown = /\.md$/i.test(filename);
    const payload = isMarkdown ? `\uFEFF${content}` : content;
    // 不使用 data URL：部分 X 浏览器会把 data URL 的编码内容原样保存，
    // 导致文件开头出现 %EF%BB%BF%23 等字符串。File/Blob 下载能保持原始 UTF-8 文本。
    let file;
    try {
      file = new File([payload], filename, { type: mime });
    } catch (_) {
      file = new Blob([payload], { type: mime });
    }
    const url = URL.createObjectURL(file);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.setAttribute('download', filename);
    link.type = mime;
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }

  function scanPerformanceRequests() {
    const entries = performance.getEntriesByType('resource') || [];
    const urls = [...new Set(entries.map((entry) => entry.name).filter(isTargetUrl))];
    return Promise.all(urls.map(async (url, requestOrder) => {
      if (state.seenUrls.has(url)) return;
      try {
        const response = await fetch(url, { credentials: 'include' });
        ingest(url, await response.text(), requestOrder);
      } catch (_) {}
    }));
  }

  function questionUrlCandidates(answer) {
    const values = [];
    const keys = [answer && answer.key, answer && answer.id]
      .filter((value) => value != null && String(value) !== '')
      .map(String);
    const templates = [
      ...state.questionUrlTemplates,
      ...state.answerUrlTemplates,
    ];

    templates.forEach((template) => {
      keys.forEach((key) => {
        try {
          const url = new URL(template, location.href);
          url.pathname = '/combine/static/solution';
          url.searchParams.set('key', key);
          url.searchParams.delete('format');
          if (!url.searchParams.has('type')) url.searchParams.set('type', '1');
          values.push(url.href);
        } catch (_) {}
      });
    });
    return [...new Set(values)];
  }

  async function fetchQuestionForAnswer(answer) {
    const identity = answerIdentity(answer);
    if (!identity || state.fetchingKeys.has(identity)) return false;
    state.fetchingKeys.add(identity);
    try {
      for (const url of questionUrlCandidates(answer)) {
        if (state.fetchedQuestionUrls.has(url)) continue;
        state.fetchedQuestionUrls.add(url);
        try {
          const response = await fetch(url, { credentials: 'include' });
          if (!response.ok) continue;
          const result = ingest(url, await response.text());
          if (result.questions > 0) return true;
        } catch (_) {}
      }
    } finally {
      state.fetchingKeys.delete(identity);
    }
    return false;
  }

  async function hydrateMissingQuestions() {
    await scanPerformanceRequests();
    const missing = allAnswers().filter((answer) => !findQuestion(answer));
    if (!missing.length) return { attempted: 0, loaded: 0 };

    const hasTemplate = state.questionUrlTemplates.size || state.answerUrlTemplates.size;
    if (!hasTemplate) return { attempted: 0, loaded: 0 };

    state.hydrating = true;
    updatePanel();
    let nextIndex = 0;
    let loaded = 0;
    const worker = async () => {
      while (nextIndex < missing.length) {
        const answer = missing[nextIndex++];
        if (await fetchQuestionForAnswer(answer)) loaded += 1;
        updatePanel();
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    state.hydrating = false;
    updatePanel();
    return { attempted: missing.length, loaded };
  }

  let shadowRoot;
  let panel;

  async function runExport(buttonId, exporter, includeAll) {
    if (state.hydrating) return;
    const button = shadowRoot && shadowRoot.querySelector(buttonId);
    const originalText = button ? button.textContent : '';
    if (button) button.textContent = '补齐题目中…';
    try {
      await hydrateMissingQuestions();
      exporter(includeAll);
    } finally {
      if (button) button.textContent = originalText;
      updatePanel();
    }
  }

  function createPanel() {
    if (panel) return;
    const host = document.createElement('div');
    host.id = 'kncard-fenbi-exporter';
    (document.body || document.documentElement).appendChild(host);
    shadowRoot = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host;
    shadowRoot.innerHTML = `<style>:host{all:initial}.box{position:fixed;right:12px;bottom:14px;z-index:2147483647;width:270px;background:#fff;color:#222;border:1px solid #d9d9d9;border-radius:12px;box-shadow:0 5px 24px #0003;font:14px/1.4 system-ui,-apple-system,"Noto Sans SC",sans-serif;padding:10px}.title{font-weight:700;margin-bottom:6px}.stats{color:#666;font-size:12px;margin-bottom:8px}.buttons{display:grid;grid-template-columns:1fr 1fr;gap:6px}button{border:0;border-radius:8px;padding:9px 5px;background:#f0f2f5;color:#222;font:inherit;touch-action:manipulation}button.primary{background:#1677ff;color:#fff}.wide{grid-column:1/-1}button:active{opacity:.75}</style><div class="box"><div class="title">粉笔错题导出</div><div class="stats" id="stats">正在等待接口数据…</div><div class="buttons"><button class="wide" id="scan">重新读取页面请求</button><button class="wide" id="fill">补齐所有题目</button><button class="primary" id="md">导出错题 MD</button><button id="json">导出错题 JSON</button><button id="html">导出错题 HTML</button><button id="all">导出全部答案 JSON</button></div></div>`;
    panel = shadowRoot.querySelector('.box');
    shadowRoot.querySelector('#scan').addEventListener('click', async () => {
      const button = shadowRoot.querySelector('#scan');
      button.textContent = '读取中…';
      await scanPerformanceRequests();
      button.textContent = '重新读取页面请求';
      updatePanel();
    });
    shadowRoot.querySelector('#fill').addEventListener('click', async () => {
      const button = shadowRoot.querySelector('#fill');
      button.textContent = '补齐中…';
      await hydrateMissingQuestions();
      button.textContent = '补齐所有题目';
      updatePanel();
    });
    shadowRoot.querySelector('#md').addEventListener('click', () => runExport('#md', exportMarkdown, false));
    shadowRoot.querySelector('#json').addEventListener('click', () => runExport('#json', exportJson, false));
    shadowRoot.querySelector('#html').addEventListener('click', () => runExport('#html', exportHtml, false));
    shadowRoot.querySelector('#all').addEventListener('click', () => runExport('#all', exportJson, true));
    updatePanel();
  }

  function updatePanel() {
    if (!shadowRoot) return;
    const total = allQuestions().length;
    const answers = allAnswers().length;
    const wrong = rows(false).length;
    const matched = allAnswers().filter(findQuestion).length;
    const missing = Math.max(0, answers - matched);
    const stats = shadowRoot.querySelector('#stats');
    if (stats) stats.textContent = state.hydrating
      ? `正在补齐… 题目 ${total} · 答案 ${answers}`
      : `题目 ${total} · 答案 ${answers} · 未获取 ${missing} · 错题 ${wrong}`;
  }

  window.addEventListener('message', (event) => {
    if (event.source !== window || !event.data || event.data.source !== MESSAGE_SOURCE) return;
    if (event.data.type === 'response' && isTargetUrl(event.data.url)) {
      ingest(event.data.url, event.data.body, event.data.requestOrder);
    }
  });

  injectPageHook();
  const startPanel = () => {
    createPanel();
    scanPerformanceRequests();
  };
  if (document.body) startPanel();
  else document.addEventListener('DOMContentLoaded', startPanel, { once: true });
})();
