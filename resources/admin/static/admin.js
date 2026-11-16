/* Cangmo admin client — original, dependency-free JavaScript. */
(function () {
  "use strict";

  var sidebar = document.getElementById("admin-sidebar");
  var navToggle = document.getElementById("admin-nav-toggle");
  if (sidebar && navToggle) {
    navToggle.addEventListener("click", function () {
      var open = sidebar.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    sidebar.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        if (window.innerWidth <= 820) sidebar.classList.remove("open");
      });
    });
  }

  document.querySelectorAll("form[data-confirm]").forEach(function (form) {
    form.addEventListener("submit", function (event) {
      var message = form.getAttribute("data-confirm") || "确定执行此操作？";
      if (!window.confirm(message)) {
        event.preventDefault();
      }
    });
  });

  document.querySelectorAll(".toast").forEach(function (toast) {
    setTimeout(function () {
      toast.style.transition = "opacity .3s, transform .3s";
      toast.style.opacity = "0";
      toast.style.transform = "translateY(-4px)";
      setTimeout(function () { toast.remove(); }, 320);
    }, 6000);
  });

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var area = document.createElement("textarea");
    area.value = text;
    document.body.appendChild(area);
    area.select();
    try { document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(area);
    return Promise.resolve();
  }

  document.querySelectorAll(".copy-url").forEach(function (button) {
    button.addEventListener("click", function () {
      var url = button.getAttribute("data-url") || "";
      copyText(url).then(function () {
        var original = button.textContent;
        button.textContent = "已复制";
        setTimeout(function () { button.textContent = original; }, 1500);
      });
    });
  });

  var dropZone = document.getElementById("drop-zone");
  if (dropZone) {
    var fileInput = dropZone.querySelector("input[type=file]");
    ["dragenter", "dragover"].forEach(function (name) {
      dropZone.addEventListener(name, function (event) {
        event.preventDefault();
        dropZone.classList.add("dragover");
      });
    });
    ["dragleave", "drop"].forEach(function (name) {
      dropZone.addEventListener(name, function (event) {
        event.preventDefault();
        dropZone.classList.remove("dragover");
      });
    });
    dropZone.addEventListener("drop", function (event) {
      if (fileInput && event.dataTransfer && event.dataTransfer.files.length) {
        fileInput.files = event.dataTransfer.files;
      }
    });
    if (fileInput) {
      fileInput.addEventListener("change", function () {
        var label = dropZone.querySelector("strong");
        if (label && fileInput.files.length) {
          label.textContent = fileInput.files.length + " 个文件已选择";
        }
      });
    }
  }

  // ---------------------------------------------------------------------
  // Editor
  // ---------------------------------------------------------------------
  var form = document.getElementById("editor-form");
  var textarea = document.getElementById("post-content");
  if (!form || !textarea) return;

  var preview = document.getElementById("preview-pane");
  var previewUrl = form.getAttribute("data-preview-url") || "/admin/preview";
  var csrf = form.getAttribute("data-csrf") || "";
  var postId = form.getAttribute("data-post-id") || "new";
  var draftKey = "cangmo-draft-" + (postId || "new");
  var tabButtons = form.querySelectorAll("[data-editor-tab]");
  var statusSelect = document.getElementById("post-status");
  var scheduleField = document.getElementById("schedule-field");
  var titleInput = document.getElementById("post-title");
  var slugInput = document.getElementById("post-slug");
  var wordCount = document.getElementById("word-count");
  var restoreButton = document.getElementById("restore-draft");
  var saveTimer = null;

  function updateScheduleVisibility() {
    if (!statusSelect || !scheduleField) return;
    var visible = statusSelect.value === "scheduled";
    scheduleField.style.display = visible ? "" : "none";
  }
  if (statusSelect) {
    statusSelect.addEventListener("change", updateScheduleVisibility);
    updateScheduleVisibility();
  }

  function updateWordCount() {
    if (!wordCount) return;
    var text = textarea.value || "";
    var cjk = (text.match(/[\u3400-\u9fff]/g) || []).length;
    var words = (text.match(/[A-Za-z0-9_]+/g) || []).length;
    wordCount.textContent = (cjk + words) + " 字";
  }
  updateWordCount();

  function showWrite() {
    textarea.hidden = false;
    preview.hidden = true;
    tabButtons.forEach(function (button) {
      button.classList.toggle("active", button.getAttribute("data-editor-tab") === "write");
    });
  }

  function showPreview() {
    textarea.hidden = true;
    preview.hidden = false;
    tabButtons.forEach(function (button) {
      button.classList.toggle("active", button.getAttribute("data-editor-tab") === "preview");
    });
    preview.innerHTML = "<p class=\"muted\">正在渲染…</p>";
    fetch(previewUrl, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf
      },
      body: JSON.stringify({ markdown: textarea.value })
    }).then(function (response) {
      if (!response.ok) throw new Error("preview failed");
      return response.json();
    }).then(function (data) {
      preview.innerHTML = data.html || "<p class=\"muted\">没有内容。</p>";
    }).catch(function () {
      preview.innerHTML = "<p class=\"muted\">预览失败，请稍后再试。</p>";
    });
  }

  tabButtons.forEach(function (button) {
    button.addEventListener("click", function () {
      if (button.getAttribute("data-editor-tab") === "preview") showPreview(); else showWrite();
    });
  });

  form.querySelectorAll(".editor-toolbar button").forEach(function (button) {
    button.addEventListener("click", function () {
      var insert = button.getAttribute("data-insert") || "";
      var wrap = button.getAttribute("data-wrap") === "1";
      var line = button.getAttribute("data-line") === "1";
      var start = textarea.selectionStart;
      var end = textarea.selectionEnd;
      var selected = textarea.value.slice(start, end);
      var replacement = insert;
      var cursor = start + insert.length;
      if (wrap) {
        replacement = insert + selected + insert;
        cursor = start + insert.length + selected.length;
      } else if (line) {
        var before = textarea.value.lastIndexOf("\n", start - 1) + 1;
        textarea.value = textarea.value.slice(0, before) + insert + textarea.value.slice(before);
        cursor = start + insert.length;
        textarea.focus();
        textarea.setSelectionRange(cursor, cursor);
        updateWordCount();
        textarea.dispatchEvent(new Event("input"));
        return;
      } else if (selected && insert.indexOf("链接文字") >= 0) {
        replacement = insert.replace("链接文字", selected);
        cursor = start + replacement.length;
      }
      textarea.value = textarea.value.slice(0, start) + replacement + textarea.value.slice(end);
      textarea.focus();
      textarea.setSelectionRange(cursor, cursor);
      updateWordCount();
      textarea.dispatchEvent(new Event("input"));
    });
  });

  if (titleInput && slugInput) {
    titleInput.addEventListener("input", function () {
      if (slugInput.value.trim().length > 0) return;
      var slug = titleInput.value.toLowerCase()
        .replace(/['"”’]/g, "")
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 80);
      if (slug.length > 0) slugInput.placeholder = slug;
    });
  }

  form.querySelectorAll(".tag-pill").forEach(function (button) {
    button.addEventListener("click", function () {
      var tag = button.getAttribute("data-tag") || "";
      var input = form.querySelector("input[name=tags]");
      if (!input) return;
      var current = input.value.split(",").map(function (item) { return item.trim(); }).filter(Boolean);
      if (current.indexOf(tag) < 0) current.push(tag);
      input.value = current.join(", ");
    });
  });

  function saveDraft() {
    try {
      localStorage.setItem(draftKey, JSON.stringify({
        title: titleInput ? titleInput.value : "",
        content: textarea.value,
        at: Date.now()
      }));
      if (restoreButton) restoreButton.hidden = false;
    } catch (e) {}
  }

  textarea.addEventListener("input", function () {
    updateWordCount();
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(saveDraft, 1200);
  });
  if (titleInput) {
    titleInput.addEventListener("input", function () {
      if (saveTimer) clearTimeout(saveTimer);
      saveTimer = setTimeout(saveDraft, 1200);
    });
  }

  if (restoreButton) {
    try {
      var storedDraft = localStorage.getItem(draftKey);
      if (storedDraft) restoreButton.hidden = false;
    } catch (e) {}
    restoreButton.addEventListener("click", function () {
      try {
        var raw = localStorage.getItem(draftKey);
        if (!raw) return;
        var draft = JSON.parse(raw);
        if (!draft || typeof draft.content !== "string") return;
        if (!window.confirm("用本地草稿覆盖当前编辑内容？")) return;
        textarea.value = draft.content || "";
        if (titleInput && draft.title) titleInput.value = draft.title;
        updateWordCount();
      } catch (e) {}
    });
  }

  window.addEventListener("beforeunload", function () {
    saveDraft();
  });
})();
