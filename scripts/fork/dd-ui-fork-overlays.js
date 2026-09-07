/**
 * Fork overlays loaded by the extension HTML inject (survives upstream UI
 * asset refreshes as long as this file is synced into ui_assets_path).
 *
 * - Strip matching "…" / '…' wrappers on Add-database Path (and Data path).
 * - zh-CN UI strings via /dd-ui-fork-i18n-zh-CN.json + MutationObserver.
 */
(function () {
  if (window.__DUCKDB_UI_FORK_OVERLAYS__) return;
  window.__DUCKDB_UI_FORK_OVERLAYS__ = true;

  /* ---------- path quotes ---------- */

  function stripWrappingQuotes(value) {
    if (typeof value !== "string") return value;
    var s = value.trim();
    if (s.length < 2) return value;
    var a = s.charAt(0);
    var b = s.charAt(s.length - 1);
    if ((a === '"' && b === '"') || (a === "'" && b === "'")) {
      return s.slice(1, -1);
    }
    return value;
  }

  function setNativeInputValue(el, value) {
    var proto = HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto, "value");
    if (desc && desc.set) {
      desc.set.call(el, value);
    } else {
      el.value = value;
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function normalizePathInputs(root) {
    if (!root || !root.querySelectorAll) return;
    var nodes = root.querySelectorAll(
      '#add-database-form input[name="path"], #add-database-form input[name="dataPath"], form#add-database-form input[aria-label="Path"], form#add-database-form input[aria-label="路径"]'
    );
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var next = stripWrappingQuotes(el.value);
      if (next !== el.value) setNativeInputValue(el, next);
    }
  }

  document.addEventListener(
    "submit",
    function (ev) {
      var form = ev.target;
      if (!form || form.id !== "add-database-form") return;
      normalizePathInputs(form);
    },
    true
  );

  document.addEventListener(
    "focusout",
    function (ev) {
      var el = ev.target;
      if (!el || el.tagName !== "INPUT") return;
      if (el.name !== "path" && el.name !== "dataPath") return;
      var form = el.closest("#add-database-form");
      if (!form) return;
      var next = stripWrappingQuotes(el.value);
      if (next !== el.value) setNativeInputValue(el, next);
    },
    true
  );

  /* ---------- zh-CN i18n ---------- */

  var ATTRS = ["placeholder", "title", "aria-label", "aria-placeholder", "alt"];
  var dict = null;
  var translating = false;
  // Dynamic strings that cannot be exact-matched in the dictionary.
  var ERROR_PREFIX_RE =
    /^(Binder Error|Catalog Error|Parser Error|Conversion Error|Invalid Input Error|Internal Exception|IO Error|Permission Error|TransactionContext Error|Dependency Error|Fatal Exception|HTTP Exception|Out of Range Error|Serialization Error|Constraint Exception|Invalid Type Error|Out of Memory Error|Interrupt Exception|Invalid Error):\s*/;
  var ERROR_PREFIX_ZH = {
    "Binder Error": "绑定错误",
    "Catalog Error": "目录错误",
    "Parser Error": "解析错误",
    "Conversion Error": "转换错误",
    "Invalid Input Error": "无效输入错误",
    "Internal Exception": "内部异常",
    "IO Error": "IO 错误",
    "Permission Error": "权限错误",
    "TransactionContext Error": "事务错误",
    "Dependency Error": "依赖错误",
    "Fatal Exception": "致命异常",
    "HTTP Exception": "HTTP 异常",
    "Out of Range Error": "越界错误",
    "Serialization Error": "序列化错误",
    "Constraint Exception": "约束异常",
    "Invalid Type Error": "无效类型错误",
    "Out of Memory Error": "内存不足",
    "Interrupt Exception": "中断异常",
    "Invalid Error": "无效错误"
  };
  var PATTERNS = [
    {
      re: /^(.+?) of this column is null$/,
      fmt: function (m) {
        return "此列有 " + m[1] + " 为空值";
      }
    },
    {
      re: /^Query in (current|new) notebook$/,
      fmt: function (m) {
        return "在" + (m[1] === "current" ? "当前" : "新") + "笔记本中查询";
      }
    },
    {
      re: /^Database (.+) detached \u2013 attach to query$/,
      fmt: function (m) {
        return "数据库 " + m[1] + " 已分离 – 附加后才能查询";
      }
    },
    {
      re: /^Are you sure you want to delete "(.+)"\? This action cannot be undone\.$/,
      fmt: function (m) {
        return "确定要删除“" + m[1] + "”吗？此操作无法撤销。";
      }
    },
    {
      re: /^Detach (.+)\?$/,
      fmt: function (m) {
        return "分离 " + m[1] + "？";
      }
    },
    {
      re: /^Unable to detach database (.+)$/,
      fmt: function (m) {
        return "无法分离数据库 " + m[1];
      }
    },
    {
      re: /^Unable to detach (.+)$/,
      fmt: function (m) {
        return "无法分离 " + m[1];
      }
    },
    {
      re: /^Successfully detached database (.+)$/,
      fmt: function (m) {
        return "已成功分离数据库 " + m[1];
      }
    },
    {
      re: /^Successfully detached (.+)$/,
      fmt: function (m) {
        return "已成功分离 " + m[1];
      }
    },
    {
      re: /^Cell running for (.+)$/,
      fmt: function (m) {
        return "单元格已运行 " + m[1];
      }
    },
    {
      re: /^Cannot detach database "(.+)" because it is the default database\. Select a different database using [`'"]?USE[`'"]? to allow detaching this database\.?$/,
      fmt: function (m) {
        return (
          "无法分离数据库“" +
          m[1] +
          "”，因为它是默认数据库。请先使用 USE 选择其他数据库，然后再分离此数据库。"
        );
      }
    },
    {
      re: /^Copy first (.+) rows to clipboard$/,
      fmt: function (m) {
        return "复制前 " + m[1] + " 行到剪贴板";
      }
    },
    {
      re: /^Download first (.+) rows$/,
      fmt: function (m) {
        return "下载前 " + m[1] + " 行";
      }
    },
    {
      re: /^Copy results \((\d[\d,]*) rows?\) to clipboard$/,
      fmt: function (m) {
        return "复制结果（" + m[1] + " 行）到剪贴板";
      }
    },
    {
      re: /^Download results \((\d[\d,]*) rows?\)$/,
      fmt: function (m) {
        return "下载结果（" + m[1] + " 行）";
      }
    },
    {
      re: /^First (\d[\d,]*) rows returned(?:, (\d+) statements run)?$/,
      fmt: function (m) {
        return (
          "前 " +
          m[1] +
          " 行返回" +
          (m[2] ? "，已运行 " + m[2] + " 条语句" : "")
        );
      }
    },
    {
      re: /^(\d[\d,]*) of (\d[\d,]*) rows returned(?:, (\d+) statements run)?$/,
      fmt: function (m) {
        return (
          m[1] +
          " / " +
          m[2] +
          " 行返回" +
          (m[3] ? "，已运行 " + m[3] + " 条语句" : "")
        );
      }
    },
    {
      re: /^(\d[\d,]*) rows? returned(?:, (\d+) statements run)?$/,
      fmt: function (m) {
        return (
          m[1] + " 行返回" + (m[2] ? "，已运行 " + m[2] + " 条语句" : "")
        );
      }
    },
    {
      re: /^(\d[\d,]*) columns?$/,
      fmt: function (m) {
        return m[1] + " 列";
      }
    },
    {
      re: /^(\d[\d,]*) rows?$/,
      fmt: function (m) {
        return m[1] + " 行";
      }
    },
    {
      re: /^(\d+(?:\.\d+)?)ms$/,
      fmt: function (m) {
        return m[1] + " 毫秒";
      }
    },
    {
      re: /^(\d+(?:\.\d+)?)s$/,
      fmt: function (m) {
        return m[1] + " 秒";
      }
    },
    {
      re: /^(\d+)m (\d+)s$/,
      fmt: function (m) {
        return m[1] + " 分 " + m[2] + " 秒";
      }
    }
  ];

  function matchPatterns(source) {
    for (var i = 0; i < PATTERNS.length; i++) {
      var m = source.match(PATTERNS[i].re);
      if (m) return PATTERNS[i].fmt(m);
    }
    return null;
  }

  // zh-CN display: group digits by 4 (万分位) instead of 3 (千分位).
  // e.g. 380,959 → 38,0959 ; 50,000 → 5,0000
  function formatWithWanSeparator(numLike) {
    var digits = String(numLike).replace(/,/g, "");
    if (!/^\d+$/.test(digits)) return null;
    var out = "";
    while (digits.length > 4) {
      out = "," + digits.slice(-4) + out;
      digits = digits.slice(0, -4);
    }
    return digits + out;
  }

  function reformatThousandsToWanInText(text) {
    // Only rewrite thousand-grouping (groups of 3). Do not touch 万分位 (groups of 4).
    return String(text).replace(/(?<!\d)\d{1,3}(?:,\d{3})+(?!\d)/g, function (chunk) {
      return formatWithWanSeparator(chunk) || chunk;
    });
  }

  function translateText(text) {
    if (!dict || text == null) return null;
    var raw = String(text);
    if (!raw) return null;

    var trimmed = raw.trim();
    var out = null;

    if (dict[raw] != null) {
      out = dict[raw];
    } else if (dict[trimmed] != null) {
      out = dict[trimmed];
    } else {
      out = matchPatterns(trimmed);
      if (out == null) {
        // DuckDB engine errors: "Binder Error: …" etc. — strip prefix, translate body.
        var pre = trimmed.match(ERROR_PREFIX_RE);
        if (pre) {
          var body = trimmed.slice(pre[0].length);
          var bodyOut = dict[body] != null ? dict[body] : matchPatterns(body);
          if (bodyOut != null) {
            out = (ERROR_PREFIX_ZH[pre[1]] || pre[1]) + "：" + bodyOut;
          }
        }
      }
      if (out == null) {
        var reformattedOnly = reformatThousandsToWanInText(trimmed);
        if (reformattedOnly !== trimmed) out = reformattedOnly;
      }
    }

    if (out == null) return null;
    out = reformatThousandsToWanInText(out);
    if (trimmed !== raw) out = raw.replace(trimmed, out);
    return out === raw ? null : out;
  }

  function translateElement(el) {
    if (!el || el.nodeType !== 1) return;
    if (el.closest && el.closest("script, style, code, pre, .cm-editor, .cm-content, textarea, input, [contenteditable='true']")) {
      // Still translate attrs on inputs; skip text content of editors.
      if (el.tagName !== "INPUT" && el.tagName !== "TEXTAREA") return;
    }

    for (var i = 0; i < ATTRS.length; i++) {
      var name = ATTRS[i];
      if (!el.hasAttribute(name)) continue;
      var cur = el.getAttribute(name);
      var next = translateText(cur);
      if (next != null && next !== cur) el.setAttribute(name, next);
    }

    if (el.tagName === "INPUT" || el.tagName === "TEXTAREA") return;

    // Leaf-ish: translate direct text nodes only (avoid breaking mixed markup).
    var child = el.firstChild;
    while (child) {
      var nextSibling = child.nextSibling;
      if (child.nodeType === 3) {
        var t = child.nodeValue;
        var tr = translateText(t);
        if (tr != null && tr !== t) child.nodeValue = tr;
      }
      child = nextSibling;
    }
  }

  function walk(root) {
    if (!dict || !root) return;
    translating = true;
    try {
      if (root.nodeType === 1) translateElement(root);
      var all = root.querySelectorAll ? root.querySelectorAll("*") : [];
      for (var i = 0; i < all.length; i++) translateElement(all[i]);
    } finally {
      translating = false;
    }
  }

  function startI18n(map) {
    dict = map || {};
    try {
      document.documentElement.setAttribute("lang", "zh-CN");
    } catch (e) {}
    walk(document.documentElement);
    var obs = new MutationObserver(function (mutations) {
      if (translating) return;
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === "characterData" && m.target && m.target.parentElement) {
          translateElement(m.target.parentElement);
        } else if (m.type === "childList") {
          for (var j = 0; j < m.addedNodes.length; j++) {
            var n = m.addedNodes[j];
            if (n.nodeType === 1) walk(n);
            else if (n.nodeType === 3 && n.parentElement) translateElement(n.parentElement);
          }
        } else if (m.type === "attributes" && m.target) {
          translateElement(m.target);
        }
      }
    });
    obs.observe(document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ATTRS
    });
  }

  fetch("/dd-ui-fork-i18n-zh-CN.json", { cache: "no-cache" })
    .then(function (r) {
      if (!r.ok) throw new Error("i18n " + r.status);
      return r.json();
    })
    .then(startI18n)
    .catch(function () {
      /* Path-quote support still active without dictionary. */
    });
})();
