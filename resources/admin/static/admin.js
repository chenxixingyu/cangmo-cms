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

  // Command palette: quick navigation and common actions.
  var commandDialog = document.getElementById("command-dialog");
  var commandInput = document.getElementById("command-input");
  var commandList = document.getElementById("command-list");
  var commandOpen = document.getElementById("command-open");
  if (commandDialog && commandInput && commandList) {
    var commands = [
      { label: "仪表盘", url: "/admin", hint: "概览" },
      { label: "文章", url: "/admin/posts", hint: "内容列表" },
      { label: "页面", url: "/admin/posts?type=page", hint: "独立页面" },
      { label: "新建文章", url: "/admin/posts/new", hint: "写文章" },
      { label: "新建页面", url: "/admin/posts/new?type=page", hint: "创建页面" },
      { label: "评论", url: "/admin/comments", hint: "审核与回复" },
      { label: "附件库", url: "/admin/attachments", hint: "图片与文件" },
      { label: "用户", url: "/admin/users", hint: "成员与角色" },
      { label: "设置", url: "/admin/settings", hint: "站点信息、外观、评论" },
      { label: "主题", url: "/admin/themes", hint: "切换主题" },
      { label: "审计日志", url: "/admin/audit", hint: "操作记录" },
      { label: "工具", url: "/admin/tools", hint: "运行信息与导出" },
      { label: "重定向", url: "/admin/redirects", hint: "旧链接 301" },
      { label: "Markdown 导入", url: "/admin/import", hint: "批量导入" },
      { label: "备份中心", url: "/admin/backups", hint: "创建与恢复" }
    ];

    function renderCommands(query) {
      var needle = (query || "").trim().toLowerCase();
      commandList.innerHTML = "";
      var matched = commands.filter(function (item) {
        return needle.length === 0 || (item.label + " " + item.hint).toLowerCase().includes(needle);
      });
      matched.forEach(function (item) {
        var link = document.createElement("a");
        link.href = item.url;
        link.className = "command-item";
        var label = document.createElement("strong");
        label.textContent = item.label;
        var hint = document.createElement("span");
        hint.textContent = item.hint;
        link.appendChild(label);
        link.appendChild(hint);
        commandList.appendChild(link);
      });
      if (matched.length === 0) {
        var empty = document.createElement("p");
        empty.className = "muted small";
        empty.textContent = "没有匹配的页面或操作。";
        commandList.appendChild(empty);
      }
    }

    function openCommand() {
      renderCommands("");
      commandInput.value = "";
      commandDialog.showModal();
      commandInput.focus();
    }

    if (commandOpen) {
      commandOpen.addEventListener("click", openCommand);
    }
    commandInput.addEventListener("input", function () { renderCommands(commandInput.value); });
    commandInput.addEventListener("keydown", function (event) {
      if (event.key === "Enter") {
        var first = commandList.querySelector(".command-item");
        if (first) {
          event.preventDefault();
          window.location.href = first.getAttribute("href");
        }
      }
    });
    document.addEventListener("keydown", function (event) {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        if (commandDialog.open) commandDialog.close(); else openCommand();
      }
    });
  }

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

  // Attachment rename + reference-aware delete.
  var renameDialog = document.getElementById("attachment-rename-dialog");
  var renameForm = document.getElementById("attachment-rename-form");
  var renameInput = renameForm ? renameForm.querySelector("input[name=name]") : null;
  document.querySelectorAll(".attachment-rename").forEach(function (button) {
    button.addEventListener("click", function () {
      if (!renameDialog || !renameForm) return;
      renameForm.action = button.getAttribute("data-rename-url");
      if (renameInput) renameInput.value = button.getAttribute("data-name") || "";
      renameDialog.showModal();
      if (renameInput) renameInput.focus();
    });
  });

  var deleteDialog = document.getElementById("attachment-delete-dialog");
  var deleteForm = document.getElementById("attachment-delete-form");
  var usageSummary = document.getElementById("attachment-usage-summary");
  var usageList = document.getElementById("attachment-usage-list");
  document.querySelectorAll(".attachment-delete").forEach(function (button) {
    button.addEventListener("click", function () {
      if (!deleteDialog || !deleteForm) return;
      var usageUrl = button.getAttribute("data-usage-url");
      deleteForm.action = button.getAttribute("data-delete-url");
      if (usageSummary) usageSummary.textContent = "正在检查引用…";
      if (usageList) usageList.innerHTML = "";
      fetch(usageUrl, { headers: { "Accept": "application/json" } })
        .then(function (response) { return response.json(); })
        .then(function (data) {
          var count = (data && data.count) || 0;
          if (usageSummary) {
            usageSummary.textContent = count > 0 ? "该附件被 " + count + " 篇内容引用：" : "该附件未被内容引用。";
          }
          if (usageList) {
            (data && data.items ? data.items : []).forEach(function (item) {
              var li = document.createElement("li");
              var kind = item.type === "page" ? "页面" : "文章";
              li.textContent = item.title + "（" + kind + " · " + item.reason + "）";
              usageList.appendChild(li);
            });
          }
          deleteDialog.showModal();
        })
        .catch(function () {
          if (usageSummary) usageSummary.textContent = "无法检查引用，仍可继续删除。";
          deleteDialog.showModal();
        });
    });
  });

  var redirectCreateOpen = document.getElementById("redirect-create-open");
  var redirectCreateDialog = document.getElementById("redirect-create-dialog");
  if (redirectCreateOpen && redirectCreateDialog) {
    redirectCreateOpen.addEventListener("click", function () { redirectCreateDialog.showModal(); });
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

  // Backup dialogs: keep the page compact; open forms on demand.
  var backupCreateOpen = document.getElementById("backup-create-open");
  var backupCreateDialog = document.getElementById("backup-create-dialog");
  var backupRestoreOpen = document.getElementById("backup-restore-open");
  var backupRestoreDialog = document.getElementById("backup-restore-dialog");
  if (backupCreateOpen && backupCreateDialog) {
    backupCreateOpen.addEventListener("click", function () { backupCreateDialog.showModal(); });
  }
  if (backupRestoreOpen && backupRestoreDialog) {
    backupRestoreOpen.addEventListener("click", function () { backupRestoreDialog.showModal(); });
  }

  // ---------------------------------------------------------------------
  // Publishing drawer (editor) and inline page drawer (list)
  // ---------------------------------------------------------------------
  var publishDrawer = document.getElementById("publish-drawer");
  var publishOpen = document.getElementById("publish-drawer-open");
  if (publishDrawer && publishOpen) {
    publishOpen.addEventListener("click", function () { publishDrawer.showModal(); publishDrawer.focus(); });
    publishDrawer.querySelectorAll("[data-close-drawer]").forEach(function (button) {
      button.addEventListener("click", function () { publishDrawer.close(); });
    });
    publishDrawer.addEventListener("click", function (event) {
      if (event.target === publishDrawer) publishDrawer.close();
    });
  }

  var revisionDialog = document.getElementById("revision-dialog");
  var revisionButtons = document.querySelectorAll(".revision-view");
  if (revisionDialog && revisionButtons.length > 0) {
    var revisionRestore = document.getElementById("revision-restore");
    var revisionTitle = document.getElementById("revision-dialog-title");
    var revisionDate = document.getElementById("revision-dialog-date");
    var revisionSummary = document.getElementById("revision-dialog-summary");
    var revisionContent = document.getElementById("revision-dialog-content");
    var revisionDiff = document.getElementById("revision-dialog-diff");
    var revisionCompare = document.getElementById("revision-compare");
    var revisionError = document.getElementById("revision-dialog-error");
    var revisionUrl = "";
    var revisionText = "";

    function lineDiff(oldText, newText) {
      var a = oldText.split("\n");
      var b = newText.split("\n");
      if (a.length > 2000 || b.length > 2000) {
        return ["内容过长，已跳过行级对比。"];
      }
      var dp = [];
      for (var i = 0; i <= a.length; i += 1) {
        dp.push(new Array(b.length + 1).fill(0));
      }
      for (var i = a.length - 1; i >= 0; i -= 1) {
        for (var j = b.length - 1; j >= 0; j -= 1) {
          dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
      var out = [];
      var x = 0;
      var y = 0;
      while (x < a.length && y < b.length) {
        if (a[x] === b[y]) {
          out.push("  " + a[x]);
          x += 1;
          y += 1;
        } else if (dp[x + 1][y] >= dp[x][y + 1]) {
          out.push("- " + a[x]);
          x += 1;
        } else {
          out.push("+ " + b[y]);
          y += 1;
        }
      }
      while (x < a.length) { out.push("- " + a[x]); x += 1; }
      while (y < b.length) { out.push("+ " + b[y]); y += 1; }
      return out;
    }

    revisionButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        revisionError.textContent = "";
        fetch(button.getAttribute("data-revision-url"), { headers: { "Accept": "application/json" } })
          .then(function (response) { return response.json(); })
          .then(function (data) {
            if (!data || !data.ok) { revisionError.textContent = (data && data.error) || "加载版本失败"; return; }
            revisionUrl = button.getAttribute("data-revision-url");
            revisionTitle.textContent = data.item.title || "历史版本";
            revisionDate.textContent = data.item.date || "";
            revisionSummary.textContent = data.item.summary || "";
            revisionText = data.item.content || "";
            revisionContent.textContent = revisionText;
            revisionContent.hidden = false;
            if (revisionDiff) revisionDiff.hidden = true;
            revisionDialog.showModal();
          })
          .catch(function () { revisionError.textContent = "加载版本失败，请重试"; });
      });
    });

    revisionDialog.querySelectorAll("[data-close-revision]").forEach(function (button) {
      button.addEventListener("click", function () { revisionDialog.close(); });
    });
    revisionDialog.addEventListener("click", function (event) {
      if (event.target === revisionDialog) revisionDialog.close();
    });
    if (revisionCompare && revisionDiff) {
      revisionCompare.addEventListener("click", function () {
        if (revisionDiff.hidden) {
          var current = document.getElementById("post-content");
          revisionDiff.textContent = lineDiff(revisionText, current ? current.value : "").join("\n");
          revisionDiff.hidden = false;
          revisionContent.hidden = true;
          revisionCompare.textContent = "查看原文";
        } else {
          revisionDiff.hidden = true;
          revisionContent.hidden = false;
          revisionCompare.textContent = "对比当前";
        }
      });
    }
    if (revisionRestore) {
      revisionRestore.addEventListener("click", function () {
        if (!revisionUrl) return;
        var form = document.getElementById("editor-form");
        var csrf = form ? (form.getAttribute("data-csrf") || "") : "";
        var helper = document.createElement("form");
        helper.method = "post";
        helper.action = revisionUrl + "/restore";
        var token = document.createElement("input");
        token.type = "hidden";
        token.name = "_csrf";
        token.value = csrf;
        helper.appendChild(token);
        document.body.appendChild(helper);
        helper.submit();
      });
    }
  }

  var pageDrawer = document.getElementById("page-drawer");
  var pageForm = document.getElementById("page-drawer-form");
  var pageError = document.getElementById("page-drawer-error");
  if (pageDrawer && pageForm) {
    var pageCsrf = pageForm.getAttribute("data-csrf") || "";
    var pageCurrent = null;
    var pageLinks = document.querySelectorAll(".page-edit-link");

    function fillPage(item) {
      pageForm.elements.title.value = item.title || "";
      pageForm.elements.slug.value = item.slug || "";
      pageForm.elements.summary.value = item.summary || "";
      pageForm.elements.content.value = item.content || "";
      pageForm.elements.cover.value = item.cover || "";
      pageForm.elements.category_id.value = item.category_id || "";
      pageForm.elements.tags.value = item.tags || "";
      pageForm.elements.template.value = item.template || "";
      pageForm.elements.seo_title.value = item.seo_title || "";
      pageForm.elements.seo_description.value = item.seo_description || "";
      pageForm.elements.status.value = item.status || "draft";
      pageForm.elements.scheduled_at.value = (item.scheduled_at || "").replace(" ", "T");
      pageForm.elements.allow_comments.checked = !!item.allow_comments;
      pageError.textContent = "";
      pageDrawer.showModal();
      pageDrawer.focus();
    }

    function updatePageRow(item) {
      var row = document.querySelector('.post-row[data-post-id="' + item.id + '"]');
      if (!row) return;
      var title = row.querySelector(".table-title");
      if (title) title.textContent = item.title;
      var sub = row.querySelector(".table-sub");
      if (sub) sub.textContent = "/" + item.slug;
      var badge = row.querySelector(".status");
      if (badge) { badge.className = "status status-" + item.status; badge.textContent = item.status_text; }
      var date = row.querySelector(".js-date");
      if (date) date.textContent = item.date;
      var views = row.querySelector(".js-views");
      if (views) views.textContent = String(item.views);
    }

    pageLinks.forEach(function (link) {
      link.addEventListener("click", function (event) {
        event.preventDefault();
        fetch(link.getAttribute("data-drawer-url"), { headers: { "Accept": "application/json" } })
          .then(function (response) { return response.json(); })
          .then(function (data) {
            if (!data || !data.ok) { window.alert((data && data.error) || "加载页面失败"); return; }
            pageCurrent = data.item;
            fillPage(pageCurrent);
          })
          .catch(function () { window.alert("加载页面失败，请重试"); });
      });
    });

    pageDrawer.querySelectorAll("[data-close-page-drawer]").forEach(function (button) {
      button.addEventListener("click", function () { pageDrawer.close(); });
    });
    pageDrawer.addEventListener("click", function (event) {
      if (event.target === pageDrawer) pageDrawer.close();
    });

    pageForm.addEventListener("submit", function (event) {
      event.preventDefault();
      if (!pageCurrent) return;
      var submit = pageForm.querySelector("button[type=submit]");
      pageError.textContent = "";
      if (submit) submit.disabled = true;
      fetch("/admin/posts/" + pageCurrent.id + "/quick", {
        method: "POST",
        headers: { "X-CSRF-Token": pageCsrf, "Accept": "application/json" },
        body: new FormData(pageForm)
      })
        .then(function (response) {
          return response.json().then(function (data) { return { ok: response.ok, data: data }; });
        })
        .then(function (result) {
          if (submit) submit.disabled = false;
          if (!result.ok || !result.data.ok) {
            pageError.textContent = (result.data && result.data.error) || "保存失败";
            return;
          }
          updatePageRow(result.data.item);
          pageDrawer.close();
        })
        .catch(function () {
          if (submit) submit.disabled = false;
          pageError.textContent = "网络错误，请重试";
        });
    });
  }

  // Settings tabs: one panel at a time, all fields still submit with the form.
  var settingsTabs = document.querySelectorAll("[data-settings-tab]");
  var settingsPanels = document.querySelectorAll("[data-settings-panel]");
  if (settingsTabs.length > 0 && settingsPanels.length > 0) {
    settingsTabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        var key = tab.getAttribute("data-settings-tab");
        settingsTabs.forEach(function (item) {
          var active = item === tab;
          item.classList.toggle("active", active);
          item.setAttribute("aria-selected", active ? "true" : "false");
        });
        settingsPanels.forEach(function (panel) {
          panel.hidden = panel.getAttribute("data-settings-panel") !== key;
        });
      });
    });
  }

  // ---------------------------------------------------------------------
  // Compact admin: popover menus, bulk selection, category dialog
  // ---------------------------------------------------------------------
  // Close any open `<details>` menu when clicking outside of it.
  document.addEventListener("click", function (event) {
    document.querySelectorAll("details[open]").forEach(function (panel) {
      if (!panel.contains(event.target)) panel.open = false;
    });
  });

  // Row menus are fixed-position popovers so table overflow never clips them.
  function closeRowMenus() {
    document.querySelectorAll(".row-menu[open]").forEach(function (menu) { menu.open = false; });
  }
  function positionRowMenu(menu) {
    var pop = menu.querySelector(".row-menu-pop");
    var summary = menu.querySelector("summary");
    if (!pop || !summary) return;
    var rect = summary.getBoundingClientRect();
    var width = pop.offsetWidth;
    var height = pop.offsetHeight;
    var left = Math.min(Math.max(8, rect.right - width), window.innerWidth - width - 8);
    var top = rect.bottom + 6;
    if (top + height > window.innerHeight - 8) {
      top = Math.max(8, rect.top - height - 6);
    }
    pop.style.left = left + "px";
    pop.style.top = top + "px";
  }
  document.querySelectorAll(".row-menu").forEach(function (menu) {
    menu.classList.add("menu-floating");
    menu.addEventListener("toggle", function () {
      if (!menu.open) return;
      var pop = menu.querySelector(".row-menu-pop");
      if (pop) pop.style.visibility = "hidden";
      requestAnimationFrame(function () {
        positionRowMenu(menu);
        if (pop) pop.style.visibility = "";
      });
    });
  });
  window.addEventListener("resize", closeRowMenus);
  window.addEventListener("scroll", function (event) {
    var target = event.target;
    if (target && target.closest && target.closest(".row-menu-pop")) return;
    closeRowMenus();
  }, true);

  var bulkForm = document.getElementById("posts-bulk-form");
  var bulkToggle = document.getElementById("posts-bulk-toggle");
  var bulkClose = document.getElementById("posts-bulk-close");
  var bulkSelectAll = document.getElementById("posts-select-all");
  var postChecks = document.querySelectorAll(".post-check");
  var bulkCount = document.getElementById("posts-selected-count");

  function updateBulkCount() {
    var selected = 0;
    postChecks.forEach(function (box) { if (box.checked) selected += 1; });
    if (bulkCount) bulkCount.textContent = String(selected);
    if (bulkSelectAll) bulkSelectAll.checked = selected > 0 && selected === postChecks.length;
    return selected;
  }

  function showBulk(show) {
    if (!bulkForm) return;
    bulkForm.hidden = !show;
    var table = document.querySelector(".posts-table");
    if (table) table.classList.toggle("bulk-mode", show);
    if (!show) {
      postChecks.forEach(function (box) { box.checked = false; });
      updateBulkCount();
    }
  }

  if (bulkToggle && bulkForm) {
    bulkToggle.addEventListener("click", function () {
      var menu = bulkToggle.closest("details");
      if (menu) menu.open = false;
      showBulk(bulkForm.hidden);
    });
  }
  if (bulkClose) bulkClose.addEventListener("click", function () { showBulk(false); });
  if (bulkSelectAll) {
    bulkSelectAll.addEventListener("change", function () {
      postChecks.forEach(function (box) { box.checked = bulkSelectAll.checked; });
      updateBulkCount();
    });
  }
  postChecks.forEach(function (box) {
    box.addEventListener("change", function () {
      if (bulkForm && bulkForm.hidden) bulkForm.hidden = false;
      updateBulkCount();
    });
  });
  if (bulkForm) updateBulkCount();

  var categoryOpen = document.getElementById("category-create-open");
  var categoryDialog = document.getElementById("category-create-dialog");
  if (categoryOpen && categoryDialog) {
    categoryOpen.addEventListener("click", function () { categoryDialog.showModal(); });
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
      coverPreview.innerHTML = url ? "<img src=\"" + url + "\" alt=\"封面预览\">" : "<span>无</span>";
    }
    var label = document.getElementById("cover-label");
    if (label) label.textContent = url ? "已设置封面" : "未设置封面";
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
  ["cover-upload-button", "cover-library-button", "cover-url-button"].forEach(function (id) {
    var button = document.getElementById(id);
    if (button) {
      button.addEventListener("click", function () {
        var menu = button.closest("details");
        if (menu) menu.open = false;
      });
    }
  });

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

  // Attachment bulk selection.
  var bulkAll = document.getElementById("attachment-bulk-all");
  var bulkCount = document.getElementById("attachment-bulk-count");
  var bulkChecks = document.querySelectorAll(".bulk-check");
  function updateBulkCount() {
    var checked = 0;
    bulkChecks.forEach(function (box) { if (box.checked) checked += 1; });
    if (bulkCount) bulkCount.textContent = checked === 0 ? "未选择" : "已选 " + checked + " 项";
    if (bulkAll) bulkAll.checked = checked > 0 && checked === bulkChecks.length;
  }
  if (bulkAll) {
    bulkAll.addEventListener("change", function () {
      bulkChecks.forEach(function (box) { box.checked = bulkAll.checked; });
      updateBulkCount();
    });
  }
  bulkChecks.forEach(function (box) { box.addEventListener("change", updateBulkCount); });
  updateBulkCount();
  // User bulk selection.
  var userBulkAll = document.getElementById("user-bulk-all");
  var userBulkCount = document.getElementById("user-bulk-count");
  var userBulkChecks = document.querySelectorAll(".user-bulk-check");
  function updateUserBulkCount() {
    var checked = 0;
    userBulkChecks.forEach(function (box) { if (box.checked) checked += 1; });
    if (userBulkCount) userBulkCount.textContent = checked === 0 ? "未选择" : "已选 " + checked + " 项";
    if (userBulkAll) userBulkAll.checked = checked > 0 && checked === userBulkChecks.length;
  }
  if (userBulkAll) {
    userBulkAll.addEventListener("change", function () {
      userBulkChecks.forEach(function (box) { box.checked = userBulkAll.checked; });
      updateUserBulkCount();
    });
  }
  userBulkChecks.forEach(function (box) { box.addEventListener("change", updateUserBulkCount); });
  updateUserBulkCount();
  // Generate a client-side WebP thumbnail; browsers without canvas WebP fall back.
  document.querySelectorAll(".attachment-variant").forEach(function (button) {
    button.addEventListener("click", function () {
      var image = new Image();
      image.onload = function () {
        var width = Math.min(480, image.naturalWidth || image.width);
        var height = Math.max(1, Math.round((image.naturalHeight || image.height) * width / (image.naturalWidth || image.width)));
        var canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        canvas.getContext("2d").drawImage(image, 0, 0, width, height);
        canvas.toBlob(function (blob) {
          if (!blob) { window.alert("当前浏览器不支持 WebP 缩略图，已保留原图。"); return; }
          var tokenInput = document.querySelector("#attachment-upload-form [name=_csrf]");
          var data = new FormData();
          data.append("file", blob, "thumb.webp");
          fetch(button.getAttribute("data-variant-url"), {
            method: "POST",
            headers: { "X-CSRF-Token": tokenInput ? tokenInput.value : "" },
            body: data
          }).then(function (response) {
            if (!response.ok) throw new Error("variant failed");
            window.location.reload();
          }).catch(function () { window.alert("缩略图生成失败，请重试。"); });
        }, "image/webp", 0.82);
      };
      image.onerror = function () { window.alert("图片加载失败，无法生成缩略图。"); };
      image.src = button.getAttribute("data-url");
    });
  });