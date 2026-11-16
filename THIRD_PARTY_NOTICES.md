# Third-Party Notices / 第三方组件说明

Cangmo (仓墨) is an original implementation. No third-party source code is
vendored into this repository. The following external items are used as tools,
platform APIs, or standards:

| Item | Role | License / terms | Notes |
| --- | --- | --- | --- |
| Cangjie compiler, runtime, standard library (`cjc`, `cjpm`) | Build toolchain and runtime platform | Apache License 2.0 with Runtime Library Exception (Huawei) | Used as installed toolchain, not copied into source. |
| Windows CNG `SystemFunction036` (`advapi32.dll`) | OS CSPRNG | Operating system API | Called via a declared FFI binding; no code copied. |
| HTTP/1.1, JSON (RFC 8259), RSS 2.0, Atom, Sitemap 0.9, Markdown, HTML, CSS, ECMAScript | Open standards | Public specifications | Implemented independently from the specifications. |
| Inter font / Material icons / Bootstrap / jQuery / highlight.js / KaTeX | — | — | **Not used.** All CSS, JavaScript, SVG icons and fonts are original or system fonts. |

## 原创声明

- 本站程序、默认主题、后台界面、Markdown 渲染器、模板引擎、HTTP 服务器、
  JSON 解析器、密码哈希、存储引擎均为本项目从零编写。
- 未复制 Halo、WordPress、Ghost、Typecho、Hexo、Hugo 等项目的代码、模板、
  样式或资源。
- 页面中不引用任何第三方 CDN 资源；图标为自绘 SVG，字体使用系统字体栈。
- 如后续引入任何第三方组件，必须在本文件中登记其许可证，并确保与
  本项目许可证兼容。
