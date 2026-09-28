// Internal renderer helper. Only numeric geometry crosses the process boundary.
(() => {
  const report = globalThis.__cefImeReport;
  delete globalThis.__cefImeReport;
  let epoch = '0', last = '', scheduled = false, burst = 0;
  let mirror = null, childReport = null;
  function activeElement() {
    let el = document.activeElement;
    while (el?.shadowRoot?.activeElement) el = el.shadowRoot.activeElement;
    return el;
  }
  function frameRect(r) { return r; }
  function caret(el) {
    const box = el.getBoundingClientRect(), style = getComputedStyle(el);
    const line = parseFloat(style.lineHeight) || parseFloat(style.fontSize)*1.2 || 20;
    if (el.isContentEditable) {
      const selection = window.getSelection();
      if (selection?.rangeCount) {
        const range = selection.getRangeAt(0).cloneRange();
        range.setStart(selection.focusNode, selection.focusOffset);
        range.collapse(true);
        let rect = range.getClientRects()[0];
        if (rect?.height) return frameRect({x: rect.x, y: rect.y, width: 1, height: rect.height});
      }
      return frameRect({x: box.x + parseFloat(style.paddingLeft || 0),
                        y: box.y + parseFloat(style.paddingTop || 0), width: 1, height: line});
    }
    if (!mirror) {
      mirror = document.createElement('div');
      mirror.setAttribute('aria-hidden', 'true');
      mirror.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;left:-100000px;top:0;';
      document.documentElement.appendChild(mirror);
    }
    for (const key of ['boxSizing','width','height','fontFamily','fontSize','fontWeight','fontStyle',
        'fontVariant','letterSpacing','wordSpacing','textIndent','textAlign','textTransform','direction',
        'lineHeight','paddingTop','paddingRight','paddingBottom','paddingLeft',
        'borderTopWidth','borderRightWidth','borderBottomWidth','borderLeftWidth','borderStyle','tabSize']) {
      mirror.style[key] = style[key];
    }
    mirror.style.width = `${el.offsetWidth}px`;
    mirror.style.overflow = 'hidden';
    mirror.style.whiteSpace = el.tagName === 'INPUT' ? 'pre' : 'pre-wrap';
    mirror.style.overflowWrap = el.tagName === 'INPUT' ? 'normal' : 'break-word';
    const index = el.selectionDirection === 'backward' ? el.selectionStart : el.selectionEnd;
    const value = el.type === 'password' ? '•'.repeat(el.value.length) : el.value;
    mirror.textContent = value.slice(0, index ?? 0);
    const marker = document.createElement('span');
    marker.textContent = value.slice(index ?? 0) || '\u200b';
    mirror.appendChild(marker);
    const m = marker.getBoundingClientRect(), origin = mirror.getBoundingClientRect();
    const sx = box.width/(el.offsetWidth || box.width || 1);
    const sy = box.height/(el.offsetHeight || box.height || 1);
    return frameRect({x: box.x + (m.x-origin.x-el.scrollLeft)*sx,
      y: box.y + (m.y-origin.y-el.scrollTop)*sy, width: 1, height: line*sy});
  }
  function measure() {
    scheduled = false;
    if (!document.hasFocus()) return;
    const el = activeElement();
    if (el?.tagName === 'IFRAME' || el?.tagName === 'FRAME') {
      if (childReport?.frame === el && childReport.data[0] === epoch) relay(el, childReport.data);
      schedule();
      return;
    }
    const editable = !!el && !el.disabled && !el.readOnly &&
      (el.isContentEditable || el.tagName === 'TEXTAREA' ||
       (el.tagName === 'INPUT' && /^(text|search|url|tel|email|password|number)$/.test(el.type)));
    const r = editable ? caret(el) : null;
    const data = [epoch, editable, r?.x || 0, r?.y || 0, r?.width || 1, r?.height || 20];
    // Keep focus but omit unavailable cross-origin geometry rather than using
    // a child-frame coordinate as a main-frame coordinate.
    if (editable && !r) return;
    publish(data);
    if (burst > 0) {
      burst -= 1;
      last = '';
      schedule();
    } else if (editable) {
      schedule(); // caret and CSS/layout changes while editing
    }
  }
  function schedule() {
    if (!scheduled) { scheduled = true; requestAnimationFrame(measure); }
  }
  function publish(data) {
    const key = JSON.stringify(data);
    if (key === last) return;
    last = key;
    if (window === window.top) {
      const ratio = window.devicePixelRatio || 1;
      report(data[0], data[1], ...data.slice(2).map(v => v * ratio));
    }
    else window.parent.postMessage({kind: 'webview-cef-ime-rect', data}, '*');
  }
  function relay(frame, data) {
    const b = frame.getBoundingClientRect();
    const sx = b.width/(frame.offsetWidth || b.width || 1);
    const sy = b.height/(frame.offsetHeight || b.height || 1);
    publish([epoch, !!data[1], b.x+(frame.clientLeft+data[2])*sx,
      b.y+(frame.clientTop+data[3])*sy, data[4]*sx, data[5]*sy]);
  }
  window.addEventListener('message', event => {
    if (event.data?.kind !== 'webview-cef-ime-rect' || !document.hasFocus()) return;
    const frame = activeElement();
    if (!frame || !['IFRAME','FRAME'].includes(frame.tagName) || frame.contentWindow !== event.source) return;
    const data = event.data.data;
    if (!Array.isArray(data) || data.length !== 6 || data[0] !== epoch ||
        data.slice(2).some(v => !Number.isFinite(v))) return;
    childReport = {frame, data};
    relay(frame, data);
    schedule();
  });
  globalThis.__cefImeSetEpoch = value => { epoch = value; last = ''; schedule(); };
  globalThis.__cefImeRefresh = frames => {
    burst = Math.max(burst, Math.max(1, Math.min(12, Number(frames) || 6)));
    last = '';
    schedule();
  };
  for (const event of ['focusin','focusout','selectionchange','input','keyup','pointerup','scroll','resize']) {
    window.addEventListener(event, schedule, true);
  }
  if (globalThis.ResizeObserver) {
    const observer = new ResizeObserver(schedule);
    observer.observe(document.documentElement);
    if (document.body) observer.observe(document.body);
    window.addEventListener('focusin', () => {
      const el = activeElement();
      if (el && el !== document.body && el !== document.documentElement) {
        try { observer.observe(el); } catch (_) {}
      }
    }, true);
  }
  schedule();
})();
