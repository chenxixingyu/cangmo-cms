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
      if (!window.confirm(message)) event.preventDefault();
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
      try { url = new URL(url, window.location.origin).href; } catch (e) {}
      copyText(url).then(function () {
        var original = button.textContent;
        button.textContent = "已复制";
        setTimeout(function () { button.textContent = original; }, 1500);
      });
    });
  });

  document.querySelectorAll("[data-close-dialog]").forEach(function (button) {
    button.addEventListener("click", function () {
      var dialog = button.closest("dialog");
      if (dialog) dialog.close();
    });
  });

  document.querySelectorAll("dialog").forEach(function (dialog) {
    dialog.addEventListener("click", function (event) {
      if (event.target === dialog) dialog.close();
    });
  });

  // Attachment lightbox on the attachment library page.
  var attachmentDialog = document.getElementById("attachment-dialog");
  var attachmentDialogBody = document.getElementById("attachment-dialog-body");
  var attachmentDialogTitle = document.getElementById("attachment-dialog-title");
  if (attachmentDialog && attachmentDialogBody) {
    document.querySelectorAll("[data-preview-url]").forEach(function (button) {
      button.addEventListener("click", function () {
        var url = button.getAttribute("data-preview-url") || "";
        var kind = button.getAttribute("data-preview-kind") || "image";
        var name = button.getAttribute("data-preview-name") || "附件预览";
        attachmentDialogTitle.textContent = name;
        attachmentDialogBody.innerHTML = "";
        var node;
        if (kind === "video") {
          node = document.createElement("video");
          node.controls = true;
          node.src = url;
        } else if (kind === "audio") {
          node = document.createElement("audio");
          node.controls = true;
          node.src = url;
        } else if (kind === "document") {
          node = document.createElement("iframe");
          node.src = url;
          node.title = name;
        } else {
          node = document.createElement("img");
          node.src = url;
          node.alt = name;
        }
        attachmentDialogBody.appendChild(node);
        attachmentDialog.showModal();
      });
    });
  }

  // Bulk selection on the comments page.
  var selectAll = document.getElementById("comments-select-all");
  if (selectAll) {
    selectAll.addEventListener("change", function () {
      document.querySelectorAll('input[name="ids"][form="comments-bulk-form"]').forEach(function (box) {
        box.checked = selectAll.checked;
      });
    });
  }

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
  // Attachment picker helpers (editor cover + profile avatar)
  // ---------------------------------------------------------------------
  function loadAttachmentGrid(container, url, onPick) {
    if (!container) return;
    container.innerHTML = "<p class=\"muted small\">正在加载…</p>";
    fetch(url, { credentials: "same-origin", headers: { "Accept": "application/json" } })
      .then(function (response) {
        if (!response.ok) throw new Error("load failed");
        return response.json();
      })
      .then(function (data) {
        container.innerHTML = "";
        var items = data.items || [];
        if (!items.length) {
          container.innerHTML = "<p class=\"muted small\">没有可用附件，请先上传。</p>";
          return;
        }
        items.forEach(function (item) {
          var button = document.createElement("button");
          button.type = "button";
          button.className = "attachment-pick";
          button.title = item.original_name || "";
          var img = document.createElement("img");
          img.src = item.url;
          img.alt = item.original_name || "";
          img.loading = "lazy";
          button.appendChild(img);
          var label = document.createElement("span");
          label.textContent = item.original_name || "";
          button.appendChild(label);
          button.addEventListener("click", function () { onPick(item); });
          container.appendChild(button);
        });
      })
      .catch(function () {
        container.innerHTML = "<p class=\"muted small\">加载附件失败，请刷新重试。</p>";
      });
  }

  var profilePickerButton = document.getElementById("profile-avatar-picker");
  var profileDialog = document.getElementById("profile-avatar-dialog");
  var profileGrid = document.getElementById("profile-avatar-grid");
  var profileInput = document.getElementById("profile-avatar-input");
  var profilePreview = document.getElementById("profile-avatar-preview");
  if (profilePickerButton && profileDialog && profileGrid && profileInput) {
    profilePickerButton.addEventListener("click", function () {
      loadAttachmentGrid(profileGrid, "/admin/attachments/data?kind=image&page=1", function (item) {
        profileInput.value = item.url;
        if (profilePreview) profilePreview.innerHTML = "<img src=\"" + item.url + "\" alt=\"头像\">";
        profileDialog.close();
      });
      profileDialog.showModal();
    });
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
  var readingTime = document.getElementById("reading-time");
  var summaryInput = document.getElementById("post-summary");
  var summaryCount = document.getElementById("summary-count");
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
    var text = textarea.value || "";
    var cjk = (text.match(/[\u3400-\u9fff]/g) || []).length;
    var words = (text.match(/[A-Za-z0-9_]+/g) || []).length;
    var total = cjk + words;
    if (wordCount) wordCount.textContent = total + " 字";
    if (readingTime) readingTime.textContent = "约 " + Math.max(1, Math.ceil(total / 300)) + " 分钟";
  }
  updateWordCount();

  function updateSummaryCount() {
    if (summaryInput && summaryCount) summaryCount.textContent = String(summaryInput.value.length);
  }
  if (summaryInput) {
    summaryInput.addEventListener("input", updateSummaryCount);
    updateSummaryCount();
  }

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
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
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
        textarea.focus();
        textarea.setSelectionRange(start + insert.length, start + insert.length);
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

  // ---------------------------------------------------------------
  // Cover picker: upload / attachment library / URL
  // ---------------------------------------------------------------
  var coverInput = document.getElementById("cover-input");
  var coverPreview = document.getElementById("cover-preview");
  var coverFile = document.getElementById("cover-file");
  var coverDialog = document.getElementById("cover-dialog");
  var coverGrid = document.getElementById("cover-grid");
  var coverSearchForm = document.getElementById("cover-search-form");
  var coverSearchInput = document.getElementById("cover-search-input");
  var coverUrlRow = document.getElementById("cover-url-row");
  var coverUrlInput = document.getElementById("cover-url-input");
  var uploadUrl = form.getAttribute("data-upload-url") || "/admin/attachments/upload?format=json";

  function setCover(url) {
    if (!coverInput) return;
    coverInput.value = url || "";
    if (coverPreview) {
      coverPreview.innerHTML = url ? "<img src=\"" + url + "\" alt=\"封面预览\">" : "<span>未设置封面</span>";
    }
  }

  function fetchCoverGrid(query) {
    var q = query ? "&q=" + encodeURIComponent(query) : "";
    loadAttachmentGrid(coverGrid, "/admin/attachments/data?kind=image&page=1" + q, function (item) {
      setCover(item.url);
      if (coverDialog) coverDialog.close();
    });
  }

  var coverLibraryButton = document.getElementById("cover-library-button");
  if (coverLibraryButton && coverDialog) {
    coverLibraryButton.addEventListener("click", function () {
      fetchCoverGrid("");
      coverDialog.showModal();
    });
  }
  if (coverSearchForm) {
    coverSearchForm.addEventListener("submit", function (event) {
      event.preventDefault();
      fetchCoverGrid(coverSearchInput ? coverSearchInput.value.trim() : "");
    });
  }

  var coverUploadButton = document.getElementById("cover-upload-button");
  if (coverUploadButton && coverFile) {
    coverUploadButton.addEventListener("click", function () { coverFile.click(); });
    coverFile.addEventListener("change", function () {
      if (!coverFile.files || !coverFile.files.length) return;
      var data = new FormData();
      data.append("_csrf", csrf);
      data.append("files", coverFile.files[0]);
      coverUploadButton.disabled = true;
      coverUploadButton.textContent = "上传中…";
      fetch(uploadUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrf },
        body: data
      }).then(function (response) {
        return response.json().then(function (body) { return { ok: response.ok, body: body }; });
      }).then(function (result) {
        if (!result.ok || !result.body.ok) throw new Error(result.body.error || "上传失败");
        var item = result.body.items && result.body.items[0];
        if (item) setCover(item.url);
      }).catch(function (error) {
        window.alert(error.message || "上传失败");
      }).then(function () {
        coverUploadButton.disabled = false;
        coverUploadButton.textContent = "上传";
        coverFile.value = "";
      });
    });
  }

  var coverUrlButton = document.getElementById("cover-url-button");
  if (coverUrlButton && coverUrlRow) {
    coverUrlButton.addEventListener("click", function () { coverUrlRow.hidden = !coverUrlRow.hidden; });
  }
  var coverUrlApply = document.getElementById("cover-url-apply");
  if (coverUrlApply && coverUrlInput) {
    coverUrlApply.addEventListener("click", function () {
      var value = coverUrlInput.value.trim();
      if (!value) return;
      setCover(value);
      coverUrlRow.hidden = true;
    });
  }
  var coverRemoveButton = document.getElementById("cover-remove-button");
  if (coverRemoveButton) {
    coverRemoveButton.addEventListener("click", function () { setCover(""); });
  }

  // ---------------------------------------------------------------
  // Inline category creation
  // ---------------------------------------------------------------
  var categoryToggle = document.getElementById("category-create-toggle");
  var categoryPanel = document.getElementById("category-create");
  var categoryName = document.getElementById("category-name");
  var categorySubmit = document.getElementById("category-create-submit");
  var categoryError = document.getElementById("category-error");
  var categorySelect = document.getElementById("category-select");
  var categoryUrl = form.getAttribute("data-category-url") || "/admin/categories/quick";

  if (categoryToggle && categoryPanel) {
    categoryToggle.addEventListener("click", function () {
      categoryPanel.hidden = !categoryPanel.hidden;
      if (!categoryPanel.hidden && categoryName) categoryName.focus();
    });
  }

  function createCategory() {
    if (!categoryName || !categorySubmit) return;
    var name = categoryName.value.trim();
    if (!name) { if (categoryError) categoryError.textContent = "请输入分类名称"; return; }
    categorySubmit.disabled = true;
    if (categoryError) categoryError.textContent = "";
    fetch(categoryUrl, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ name: name })
    }).then(function (response) {
      return response.json().then(function (body) { return { ok: response.ok, body: body }; });
    }).then(function (result) {
      if (!result.ok || !result.body.ok) throw new Error(result.body.error || "创建失败");
      if (categorySelect) {
        var option = document.createElement("option");
        option.value = result.body.id;
        option.textContent = result.body.name;
        categorySelect.appendChild(option);
        categorySelect.value = result.body.id;
      }
      categoryName.value = "";
      categoryPanel.hidden = true;
    }).catch(function (error) {
      if (categoryError) categoryError.textContent = error.message || "创建失败";
    }).then(function () {
      categorySubmit.disabled = false;
    });
  }
  if (categorySubmit) categorySubmit.addEventListener("click", createCategory);
  if (categoryName) {
    categoryName.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); createCategory(); }
    });
  }

  // ---------------------------------------------------------------
  // Tag chips
  // ---------------------------------------------------------------
  var tagsInput = document.getElementById("tags-input");
  var tagChips = document.getElementById("tag-chips");
  var tagInput = document.getElementById("tag-input");
  var tagList = [];

  function parseTags(value) {
    return (value || "").split(",").map(function (item) { return item.trim(); }).filter(Boolean);
  }
  function syncTags() {
    if (tagsInput) tagsInput.value = tagList.join(", ");
    if (!tagChips) return;
    tagChips.innerHTML = "";
    tagList.forEach(function (tag) {
      var chip = document.createElement("span");
      chip.className = "tag-chip";
      chip.textContent = tag;
      var remove = document.createElement("button");
      remove.type = "button";
      remove.setAttribute("aria-label", "移除标签 " + tag);
      remove.textContent = "×";
      remove.addEventListener("click", function () {
        tagList = tagList.filter(function (item) { return item !== tag; });
        syncTags();
      });
      chip.appendChild(remove);
      tagChips.appendChild(chip);
    });
  }
  function addTag(tag) {
    var value = (tag || "").trim().replace(/^#/, "");
    if (!value || value.length > 40) return;
    if (tagList.indexOf(value) < 0) tagList.push(value);
    syncTags();
  }
  if (tagsInput) tagList = parseTags(tagsInput.value);
  syncTags();
  if (tagInput) {
    tagInput.addEventListener("keydown", function (event) {
      if (event.key === "Enter" || event.key === ",") {
        event.preventDefault();
        addTag(tagInput.value);
        tagInput.value = "";
      }
    });
  }
  form.querySelectorAll(".tag-pill").forEach(function (button) {
    button.addEventListener("click", function () {
      addTag(button.getAttribute("data-tag") || "");
    });
  });

  // ---------------------------------------------------------------
  // Keyboard save + local draft
  // ---------------------------------------------------------------
  document.addEventListener("keydown", function (event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      form.submit();
    }
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
