"use strict";

(() => {
  const fallback = {
    "name": "SketchGlide",
    "version": "0.2.0",
    "label": "0.2 Test",
    "status": "Test release",
    "signing": "Unnotarized · ad hoc signed",
    "downloadUrl": "https://github.com/12kareem2323-png/karim-ink/releases/download/v0.2.0-test/SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.dmg",
    "windowsDownloadUrl": "https://github.com/12kareem2323-png/karim-ink/releases/download/v0.2.0-test/SketchGlide-0.2.0-Windows-x64-Test.zip",
    "windowsLabel": "0.2 Test · Windows 11 x64",
    "windowsStatus": "Unsigned Test release",
    "repositoryUrl": "https://github.com/12kareem2323-png/karim-ink",
    "checksumsUrl": "https://github.com/12kareem2323-png/karim-ink/releases/download/v0.2.0-test/SHA256SUMS.txt",
    "websiteUrl": "https://karim-ink.stonyvale1.chatgpt.site",
    "previewAsset": "assets/preview.png",
    "previewKind": "screenshot",
    "donations": [
      {
        "name": "Support SketchGlide with PayPal",
        "url": "https://paypal.me/KEldamaty"
      }
    ]
  };
  let release = { ...fallback };
  const themeKey = "sketchglide-site-appearance";
  const preference = window.matchMedia("(prefers-color-scheme: dark)");
  let chosenTheme = null;
  try {
    const stored = localStorage.getItem(themeKey);
    if (stored === "light" || stored === "dark") chosenTheme = stored;
  } catch (_) { /* The site works when browser storage is unavailable. */ }

  function applyTheme() {
    const dark = chosenTheme ? chosenTheme === "dark" : preference.matches;
    if (chosenTheme) document.documentElement.dataset.theme = chosenTheme;
    else delete document.documentElement.dataset.theme;
    document.body.classList.toggle("theme-is-dark", dark);
    document.querySelectorAll("[data-theme-toggle]").forEach(button => {
      button.setAttribute("aria-label", `Switch to ${dark ? "light" : "dark"} appearance`);
      button.setAttribute("aria-pressed", String(dark));
    });
    document.querySelectorAll("[data-theme-label]").forEach(label => { label.textContent = dark ? "Light" : "Dark"; });
    const colour = document.querySelector('meta[name="theme-color"]');
    if (colour) colour.content = dark ? "#152522" : "#f5f3eb";
  }

  document.querySelectorAll("[data-theme-toggle]").forEach(button => {
    button.addEventListener("click", () => {
      chosenTheme = document.body.classList.contains("theme-is-dark") ? "light" : "dark";
      try { localStorage.setItem(themeKey, chosenTheme); } catch (_) { /* Optional preference only. */ }
      applyTheme();
    });
  });
  preference.addEventListener("change", () => { if (!chosenTheme) applyTheme(); });
  applyTheme();

  function safeHTTPS(value) {
    if (typeof value !== "string" || value.length > 2048) return null;
    try {
      const url = new URL(value);
      return url.protocol === "https:" && !url.username && !url.password && !url.port ? url.href : null;
    } catch (_) { return null; }
  }

  function repositoryURL(value) {
    const safe = safeHTTPS(value);
    if (!safe) return null;
    const url = new URL(safe);
    const parts = url.pathname.replace(/\/$/, "").replace(/\.git$/, "").split("/").filter(Boolean);
    if (url.hostname !== "github.com" || parts.length !== 2 || parts.some(part => !/^[A-Za-z0-9_.-]+$/.test(part))) return null;
    return `https://github.com/${parts.join("/")}`;
  }

  function plain(value, defaultValue, max = 140) {
    return typeof value === "string" && value.trim() ? value.trim().slice(0, max) : defaultValue;
  }

  function labelNodes(selector, value) {
    document.querySelectorAll(selector).forEach(node => { node.textContent = value; });
  }

  function replaceLeadingText(node, value) {
    const first = node.firstChild;
    if (first && first.nodeType === Node.TEXT_NODE) first.nodeValue = `${value} `;
    else node.prepend(document.createTextNode(`${value} `));
  }

  document.querySelectorAll("[data-download], [data-windows-download]").forEach(link => {
    link.addEventListener("click", event => {
      if (link.getAttribute("aria-disabled") === "true") event.preventDefault();
    });
  });

  function donationURL(item) {
    if (!item || typeof item !== "object") return null;
    const url = safeHTTPS(item.url);
    if (!url) return null;
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    const allowed = ["buymeacoffee.com", "www.buymeacoffee.com", "ko-fi.com", "www.ko-fi.com", "paypal.me", "www.paypal.me", "paypal.com", "www.paypal.com"];
    if (!allowed.includes(host) || parsed.pathname === "/") return null;
    return { name: plain(item.name, "Support development", 40), url };
  }

  function configurePreview(config) {
    if (!config.previewAsset || typeof config.previewAsset !== "string") return;
    try {
      const url = new URL(config.previewAsset, document.baseURI);
      if (url.origin !== location.origin || !/\.(png|jpe?g|webp|svg)$/i.test(url.pathname) || !url.pathname.split("/").includes("assets")) return;
      const image = document.querySelector("[data-app-preview]");
      if (!image) return;
      image.addEventListener("load", () => {
        image.hidden = false;
        const illustration = document.querySelector("[data-illustration]");
        if (illustration) illustration.hidden = true;
        image.closest(".preview-window").classList.add("has-screenshot");
        labelNodes("[data-preview-caption]", config.previewKind === "illustration" ? "Illustrated workspace · not a screenshot or engineering calculation" : "Mac workspace · example drawing");
      }, { once: true });
      image.addEventListener("error", () => { image.hidden = true; const fallbackImage = document.querySelector("[data-illustration]"); if (fallbackImage) fallbackImage.hidden = false; labelNodes("[data-preview-caption]", "Illustrated workspace · not an app screenshot"); }, { once: true });
      image.src = url.href;
    } catch (_) { /* Keep the clearly labelled illustration on invalid configuration. */ }
  }

  function applyRelease(config) {
    release = { ...fallback,
      version: plain(config.version, fallback.version, 30),
      label: plain(config.label, fallback.label, 40),
      status: plain(config.status, fallback.status),
      signing: plain(config.signing, fallback.signing),
      downloadUrl: safeHTTPS(config.downloadUrl),
      windowsDownloadUrl: safeHTTPS(config.windowsDownloadUrl),
      windowsLabel: plain(config.windowsLabel, fallback.windowsLabel, 40),
      windowsStatus: plain(config.windowsStatus, fallback.windowsStatus),
      repositoryUrl: repositoryURL(config.repositoryUrl),
      checksumsUrl: safeHTTPS(config.checksumsUrl),
      websiteUrl: safeHTTPS(config.websiteUrl),
      donations: Array.isArray(config.donations) ? config.donations.slice(0, 8).map(donationURL).filter(Boolean) : []
    };
    labelNodes("[data-release-label]", release.label);
    labelNodes("[data-release-status]", release.status);
    labelNodes("[data-signing]", release.signing);
    labelNodes("[data-windows-label]", release.windowsLabel);
    labelNodes("[data-windows-status]", release.windowsStatus);
    document.querySelectorAll("[data-download]").forEach(link => {
      if (release.downloadUrl) {
        link.href = release.downloadUrl;
        link.classList.remove("is-disabled");
        link.removeAttribute("aria-disabled");
        link.rel = "noopener noreferrer";
        replaceLeadingText(link, "Download for Mac");
      } else {
        link.removeAttribute("href");
        link.setAttribute("aria-disabled", "true");
        link.setAttribute("role", "link");
        link.classList.add("is-disabled");
        replaceLeadingText(link, "Download available after release checks");
      }
    });
    document.querySelectorAll("[data-windows-download]").forEach(link => {
      if (release.windowsDownloadUrl) {
        link.href = release.windowsDownloadUrl;
        link.classList.remove("is-disabled");
        link.removeAttribute("aria-disabled");
        link.rel = "noopener noreferrer";
        replaceLeadingText(link, "Download Windows Test");
      } else {
        link.removeAttribute("href");
        link.setAttribute("aria-disabled", "true");
        link.setAttribute("role", "link");
        link.classList.add("is-disabled");
        replaceLeadingText(link, "Windows Test preparing");
      }
    });
    document.querySelectorAll("[data-checksums]").forEach(link => {
      link.hidden = !release.checksumsUrl;
      if (release.checksumsUrl) { link.href = release.checksumsUrl; link.rel = "noopener noreferrer"; }
    });
    document.querySelectorAll("[data-release-page]").forEach(link => {
      if (release.repositoryUrl) { link.href = `${release.repositoryUrl}/releases/tag/v0.2.0-test`; link.hidden = false; }
    });
    document.querySelectorAll("[data-repository]").forEach(link => {
      link.hidden = !release.repositoryUrl;
      if (release.repositoryUrl) { link.href = release.repositoryUrl; link.rel = "noopener noreferrer"; }
    });
    document.querySelectorAll("[data-issues]").forEach(link => {
      link.hidden = !release.repositoryUrl;
      if (release.repositoryUrl) { link.href = `${release.repositoryUrl}/issues`; link.rel = "noopener noreferrer"; }
    });
    document.querySelectorAll("[data-security]").forEach(link => {
      link.hidden = !release.repositoryUrl;
      if (release.repositoryUrl) { link.href = `${release.repositoryUrl}/security`; link.rel = "noopener noreferrer"; }
    });
    document.querySelectorAll("[data-feedback-pending]").forEach(node => { node.hidden = Boolean(release.repositoryUrl); });
    const version = document.querySelector("#feedback-version");
    if (version && (!version.value || version.value === fallback.version)) version.value = release.version;
    document.querySelectorAll("[data-donations]").forEach(container => {
      container.replaceChildren();
      release.donations.forEach(item => {
        const link = document.createElement("a");
        link.href = item.url; link.textContent = item.name; link.rel = "noopener noreferrer";
        container.append(link);
      });
    });
    document.querySelectorAll("[data-donation-pending]").forEach(node => { node.hidden = release.donations.length > 0; });
    if (release.websiteUrl) {
      let canonical = document.querySelector('link[rel="canonical"]');
      if (!canonical) { canonical = document.createElement("link"); canonical.rel = "canonical"; document.head.append(canonical); }
      const page = location.pathname.split("/").pop();
      const current = ["privacy.html", "support.html", "publishing.html"].includes(page) ? page : "";
      canonical.href = new URL(current, release.websiteUrl.endsWith("/") ? release.websiteUrl : `${release.websiteUrl}/`).href;
    }
    configurePreview(config);
  }

  const brushes = {
    technical: { title: "Technical fineliner", description: "A steady, uniform line for dimensions and engineering schematics. Pressure scaling is off by design." },
    pencil: { title: "Graphite pencil", description: "A textured mark for early sketches. Adjust pencil grade, grain and pressure response; supported tablet tilt adds shading." },
    ink: { title: "Liquid ink", description: "Smooth, flowing marks with a tapered pressure response. Use colour, width and smoothing controls to suit your handwriting." },
    highlight: { title: "Highlighter", description: "A broad, translucent mark for calling attention to the working. Keep the calculation and the annotation together." }
  };
  document.querySelectorAll("[data-brush]").forEach(button => {
    button.addEventListener("click", () => {
      const key = button.dataset.brush, brush = brushes[key];
      if (!brush) return;
      document.querySelectorAll("[data-brush]").forEach(other => {
        const active = other === button; other.classList.toggle("is-active", active); other.setAttribute("aria-pressed", String(active));
      });
      labelNodes("[data-brush-title]", brush.title); labelNodes("[data-brush-description]", brush.description);
      const illustration = document.querySelector("[data-brush-example]");
      if (illustration) illustration.dataset.brushExample = key;
    });
  });

  const topics = {
    electrical: { title: "Electrical, electronics & digital logic", description: "Resistors, capacitors, sources, motors, semiconductors and logic gates — organized for notes and schematic sketches.", symbols: ["Ω", "▱", "⊕", "▷"] },
    maths: { title: "Algebra, calculus, geometry & statistics", description: "Operators, fractions, powers, integral signs, summations and Greek notation for working through engineering maths.", symbols: ["∫", "Σ", "π", "√"] },
    mechanics: { title: "Mechanical principles & forces", description: "Beams, loads, supports, springs, pulleys and gear arrangements for explaining forces and mechanisms.", symbols: ["F", "↧", "⚙", "↻"] },
    fluids: { title: "Fluid systems & measurements", description: "Pipes, pumps, valves, manometers and hydraulic components for sketching flow and pressure ideas.", symbols: ["p", "⇢", "∪", "Δ"] },
    manufacturing: { title: "Technical drawing & manufacturing", description: "Dimensions, surface finish, datums, tolerances and process diagrams. Check your required drawing conventions.", symbols: ["⌀", "⊥", "R", "⌖"] }
  };
  document.querySelectorAll("[data-topic]").forEach(button => {
    button.addEventListener("click", () => {
      const topic = topics[button.dataset.topic]; if (!topic) return;
      document.querySelectorAll("[data-topic]").forEach(other => {
        const active = other === button; other.classList.toggle("is-active", active); other.setAttribute("aria-pressed", String(active));
      });
      labelNodes("[data-topic-title]", topic.title); labelNodes("[data-topic-description]", topic.description);
      const symbols = document.querySelector("[data-topic-symbols]");
      if (symbols) {
        symbols.replaceChildren(...topic.symbols.map(symbol => { const node = document.createElement("span"); node.textContent = symbol; return node; }));
      }
    });
  });

  const feedbackForm = document.querySelector("#feedback-form");
  if (feedbackForm) {
    feedbackForm.addEventListener("submit", event => event.preventDefault());
    const field = name => {
      const input = feedbackForm.elements.namedItem(name);
      return input && typeof input.value === "string" ? input.value.trim() : "";
    };
    function report() {
      return ["SketchGlide feedback", "", `Summary: ${field("summary") || "Not entered"}`,
        `App version: ${field("version") || release.version}`, `Operating system / computer: ${field("system") || "Not entered"}`,
        `Tablet / driver (if relevant): ${field("tablet") || "Not entered"}`, "", "Steps to reproduce:", field("steps") || "Not entered",
        "", "Expected result:", field("expected") || "Not entered", "", "Actual result:", field("actual") || "Not entered", "",
        "Check before sharing: remove credentials, private drawings and personal information.", ""].join("\n");
    }
    document.querySelector("[data-copy-feedback]")?.addEventListener("click", async () => {
      try {
        if (!navigator.clipboard?.writeText) throw new Error("Clipboard unavailable");
        await navigator.clipboard.writeText(report());
        labelNodes("[data-feedback-status]", "Feedback copied. Review it before pasting into a public issue.");
      } catch (_) { labelNodes("[data-feedback-status]", "Clipboard access is unavailable. Use Save text file instead."); }
    });
    document.querySelector("[data-save-feedback]")?.addEventListener("click", () => {
      const blob = new Blob([report()], { type: "text/plain;charset=utf-8" });
      const objectURL = URL.createObjectURL(blob);
      const link = document.createElement("a"); link.href = objectURL; link.download = "SketchGlide-feedback.txt";
      document.body.append(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(objectURL), 1000);
      labelNodes("[data-feedback-status]", "Text file prepared. It has not been sent anywhere; review it before sharing.");
    });
  }

  applyRelease(fallback);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4000);
  fetch("release.json", { cache: "no-store", credentials: "same-origin", signal: controller.signal })
    .then(response => { if (!response.ok) throw new Error("Release information unavailable"); return response.json(); })
    .then(config => { if (config && typeof config === "object" && !Array.isArray(config)) applyRelease(config); })
    .catch(() => { /* Keep the verified release links already included in this site version. */ })
    .finally(() => clearTimeout(timeout));
})();
