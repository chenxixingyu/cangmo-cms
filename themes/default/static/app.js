/* Cangmo default theme client — original, dependency-free JavaScript. */
(function () {
  "use strict";

  var root = document.documentElement;
  var stored = null;
  try { stored = localStorage.getItem("cangmo-theme"); } catch (e) {}
  if (stored === "light" || stored === "dark") {
    root.setAttribute("data-theme", stored);
  }

  function effectiveDark() {
    var theme = root.getAttribute("data-theme");
    if (theme === "dark") return true;
    if (theme === "light") return false;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  var toggle = document.getElementById("theme-toggle");
  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = effectiveDark() ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("cangmo-theme", next); } catch (e) {}
      toggle.setAttribute("aria-label", next === "dark" ? "切换浅色模式" : "切换深色模式");
    });
  }

  var navToggle = document.getElementById("nav-toggle");
  var nav = document.getElementById("site-nav");
  if (navToggle && nav) {
    navToggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }

  // Copy buttons for fenced code blocks.
  document.querySelectorAll(".prose pre").forEach(function (pre) {
    var code = pre.querySelector("code");
    if (!code) return;
    var button = document.createElement("button");
    button.type = "button";
    button.className = "copy-code";
    button.textContent = "复制";
    button.addEventListener("click", function () {
      var text = code.innerText;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () {
          button.textContent = "已复制";
          setTimeout(function () { button.textContent = "复制"; }, 1600);
        });
      } else {
        var area = document.createElement("textarea");
        area.value = text;
        document.body.appendChild(area);
        area.select();
        try { document.execCommand("copy"); button.textContent = "已复制"; } catch (e) {}
        document.body.removeChild(area);
        setTimeout(function () { button.textContent = "复制"; }, 1600);
      }
    });
    pre.appendChild(button);
  });

  // Reply support for comments.
  var parentInput = document.getElementById("parent-id");
  var replyHint = document.getElementById("reply-hint");
  var replyName = document.getElementById("reply-name");
  var cancelReply = document.getElementById("cancel-reply");
  var commentForm = document.getElementById("comment-form");
  document.querySelectorAll(".reply-btn").forEach(function (button) {
    button.addEventListener("click", function () {
      if (!parentInput || !replyHint) return;
      parentInput.value = button.getAttribute("data-parent") || "";
      if (replyName) replyName.textContent = button.getAttribute("data-name") || "";
      replyHint.hidden = false;
      if (commentForm) commentForm.scrollIntoView({ behavior: "smooth", block: "start" });
      var area = commentForm ? commentForm.querySelector("textarea[name=content]") : null;
      if (area) area.focus();
    });
  });
  if (cancelReply) {
    cancelReply.addEventListener("click", function () {
      if (parentInput) parentInput.value = "";
      if (replyHint) replyHint.hidden = true;
    });
  }

  // Reading progress.
  var progress = document.getElementById("reading-progress");
  var article = document.querySelector(".prose");
  if (progress && article) {
    var update = function () {
      var rect = article.getBoundingClientRect();
      var total = rect.height - window.innerHeight;
      var scrolled = -rect.top;
      var ratio = total > 0 ? Math.min(1, Math.max(0, scrolled / total)) : 0;
      progress.style.width = (ratio * 100).toFixed(2) + "%";
    };
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  // "/" focuses search.
  document.addEventListener("keydown", function (event) {
    if (event.key !== "/" || event.ctrlKey || event.metaKey || event.altKey) return;
    var tag = (event.target && event.target.tagName) ? event.target.tagName.toLowerCase() : "";
    if (tag === "input" || tag === "textarea" || tag === "select") return;
    var input = document.querySelector(".search-form input[name=q]");
    if (input) { event.preventDefault(); input.focus(); }
  });

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("/sw.js").catch(function () {});
    });
  }
})();
