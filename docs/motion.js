"use strict";

// Scroll-driven presentation only. Nothing runs continuously while the page is idle.
(() => {
  const root = document.documentElement;
  const track = document.querySelector("[data-camera-track]");
  const camera = track?.querySelector("[data-camera]");
  const reveals = Array.from(document.querySelectorAll("[data-reveal]"));
  if (!camera && !reveals.length) return;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const compactLayout = window.matchMedia("(max-width: 760px)");
  const hasObservers = "IntersectionObserver" in window;
  const clamp = value => Math.min(1, Math.max(0, value));
  let revealObserver;
  let cameraObserver;
  let frame = 0;
  let visible = !hasObservers;
  let geometryDirty = true;
  let snapNextFrame = true;
  let trackTop = 0;
  let travel = 1;
  let progress = 0;
  let previousTime = 0;
  let lastChange = 0;
  let previousWritten = -1;

  function reveal(element) {
    element.classList.add("is-visible");
    revealObserver?.unobserve(element);
  }

  function configureReveals() {
    revealObserver?.disconnect();
    root.classList.remove("motion-ready");
    if (reducedMotion.matches || !hasObservers) {
      reveals.forEach(reveal);
      return;
    }
    revealObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => { if (entry.isIntersecting) reveal(entry.target); });
    }, { threshold: 0, rootMargin: "0px 0px -6% 0px" });
    reveals.forEach(element => {
      if (!element.classList.contains("is-visible")) revealObserver.observe(element);
    });
    // Styles remain visible if JavaScript or IntersectionObserver is unavailable.
    root.classList.add("motion-ready");
  }

  function cancelFrame() {
    if (frame) window.cancelAnimationFrame(frame);
    frame = 0;
    previousTime = 0;
  }

  function canAnimateCamera() {
    return camera && visible && !document.hidden && !reducedMotion.matches && !compactLayout.matches;
  }

  function writeCamera(value, neutral = false) {
    if (!camera) return;
    if (value === previousWritten && !neutral) return;
    previousWritten = neutral ? -1 : value;
    // CSS owns the transform; these properties cannot affect track geometry.
    const eased = value * value * (3 - 2 * value);
    track.style.setProperty("--camera-progress", value.toFixed(4));
    camera.style.setProperty("--camera-progress", value.toFixed(4));
    camera.style.setProperty("--camera-scale", neutral ? "1" : (1 + 0.62 * eased).toFixed(4));
    camera.style.setProperty("--camera-rotate-x", neutral ? "0deg" : `${(11 * (1 - eased)).toFixed(3)}deg`);
    camera.style.setProperty("--camera-rotate-y", neutral ? "0deg" : `${(-4 * (1 - eased)).toFixed(3)}deg`);
    camera.style.setProperty("--camera-y", neutral ? "0px" : `${(12 - 60 * eased).toFixed(3)}px`);
  }

  function draw(time) {
    frame = 0;
    if (!canAnimateCamera()) { previousTime = 0; return; }
    const scrollPosition = window.scrollY;
    if (geometryDirty) {
      // One geometry read on resize/content changes, never on every scroll event.
      const bounds = track.getBoundingClientRect();
      trackTop = bounds.top + scrollPosition;
      travel = Math.max(1, bounds.height - window.innerHeight);
      geometryDirty = false;
    }
    const target = clamp((scrollPosition - trackTop) / travel);
    const elapsed = previousTime ? Math.min(64, time - previousTime) : 16;
    previousTime = time;
    if (snapNextFrame || time - lastChange >= 260 || Math.abs(target - progress) < 0.0008) {
      progress = target;
      snapNextFrame = false;
    } else {
      progress += (target - progress) * (1 - Math.exp(-elapsed / 60));
    }
    writeCamera(progress);
    // The short settling tail stops after 260 ms; idle pages have no RAF loop.
    if (Math.abs(target - progress) >= 0.0008) frame = window.requestAnimationFrame(draw);
    else previousTime = 0;
  }

  function requestFrame(snap = false) {
    if (snap) snapNextFrame = true;
    if (!canAnimateCamera() || frame) return;
    frame = window.requestAnimationFrame(draw);
  }

  function invalidateGeometry() {
    geometryDirty = true;
    requestFrame(true);
  }

  function configureCamera() {
    cancelFrame();
    geometryDirty = true;
    snapNextFrame = true;
    if (camera) {
      // No retained layer while offscreen, compact, hidden, or reducing motion.
      camera.style.willChange = canAnimateCamera() ? "transform" : "auto";
      if (reducedMotion.matches || compactLayout.matches) writeCamera(0, true);
    }
    requestFrame(true);
  }

  configureReveals();
  if (camera) {
    if (hasObservers) {
      cameraObserver = new IntersectionObserver(entries => {
        const entry = entries[entries.length - 1];
        if (!entry) return;
        visible = entry.isIntersecting;
        configureCamera();
      }, { threshold: 0, rootMargin: "0px" });
      cameraObserver.observe(track);
    }
    if ("ResizeObserver" in window) {
      new ResizeObserver(invalidateGeometry).observe(track);
    }
    window.addEventListener("scroll", () => {
      if (!canAnimateCamera()) return;
      lastChange = performance.now();
      requestFrame();
    }, { passive: true });
    window.addEventListener("resize", invalidateGeometry, { passive: true });
    window.addEventListener("load", invalidateGeometry, { once: true });
    window.addEventListener("pageshow", () => configureCamera());
    window.addEventListener("pagehide", cancelFrame);
    document.fonts?.ready.then(invalidateGeometry);
    document.addEventListener("visibilitychange", configureCamera);
    compactLayout.addEventListener("change", configureCamera);
    configureCamera();
  }
  reducedMotion.addEventListener("change", () => {
    configureReveals();
    configureCamera();
  });
  document.addEventListener("focusin", event => {
    // A keyboard jump never lands in visually hidden content.
    let element = event.target instanceof Element ? event.target.closest("[data-reveal]") : null;
    while (element) {
      reveal(element);
      element = element.parentElement?.closest("[data-reveal]");
    }
  });
})();
