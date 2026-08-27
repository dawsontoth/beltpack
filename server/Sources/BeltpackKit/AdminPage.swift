#if os(macOS)

import Foundation

/// The management page, embedded rather than shipped as a file so the host is
/// a single self-contained binary with nothing to install alongside it.
///
/// No external fonts or scripts: the booth network may have no route to the
/// internet, and a control panel that only works when the building's uplink is
/// healthy is the wrong thing to depend on mid-service.
enum AdminPage {
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <title>Beltpack Host</title>
    <style>
      :root {
        --ground:#0e1116; --surface:#161b22; --sunk:#10141a; --ink:#e6eaf0;
        --muted:#8c97a5; --rule:#2a323d; --teal:#3fbfcb; --amber:#e8a33d;
        --green:#3fcb7a; --red:#e5484d; color-scheme: dark;
      }
      *{box-sizing:border-box}
      body{margin:0;background:var(--ground);color:var(--ink);
        font:15px/1.55 ui-sans-serif,-apple-system,system-ui,sans-serif;
        padding:env(safe-area-inset-top) 16px env(safe-area-inset-bottom)}
      main{max-width:720px;margin:0 auto;padding:24px 0 64px;display:flex;flex-direction:column;gap:22px}
      h1{margin:0;font-size:1.05rem;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
      h2{margin:0 0 8px;font-size:.7rem;letter-spacing:.11em;text-transform:uppercase;color:var(--muted);font-weight:600}
      .card{background:var(--surface);border:1px solid var(--rule);border-radius:8px;padding:16px}
      .row{display:flex;align-items:center;gap:12px}
      .lamp{width:12px;height:12px;border-radius:50%;background:var(--muted);flex:none}
      .lamp[data-s=running]{background:var(--green)}
      .lamp[data-s=starting],.lamp[data-s=reconnecting]{background:var(--amber)}
      .lamp[data-s=failed]{background:var(--red)}
      .grow{flex:1;min-width:0}
      .state{font-weight:600}
      .sub{color:var(--muted);font-size:.85rem;word-break:break-word}
      button{font:inherit;font-weight:600;padding:10px 16px;border:0;border-radius:7px;
        background:var(--teal);color:#04191b;cursor:pointer}
      button.ghost{background:transparent;color:var(--ink);border:1px solid var(--rule)}
      button.stop{background:var(--red);color:#fff}
      button:disabled{opacity:.45;cursor:not-allowed}
      label{display:flex;flex-direction:column;gap:6px;font-size:.78rem;color:var(--muted);margin-bottom:12px}
      select,input{font:inherit;padding:10px;color:var(--ink);background:var(--sunk);
        border:1px solid var(--rule);border-radius:7px;width:100%}
      ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column}
      li{display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--rule)}
      li:last-child{border-bottom:0}
      .dot{width:8px;height:8px;border-radius:50%;background:#39414d;flex:none}
      .dot[data-speaking=true]{background:var(--green)}
      .tag{font-size:.62rem;letter-spacing:.08em;padding:2px 6px;border-radius:99px;
        background:#222c37;color:var(--muted);font-weight:600}
      .mic{margin-left:auto;font-size:.78rem;color:var(--muted)}
      .mic[data-live=true]{color:var(--green)}
      .qr{display:flex;gap:20px;flex-wrap:wrap;justify-content:center}
      .qr figure{margin:0;text-align:center}
      .qr svg{width:190px;height:190px;border-radius:6px;display:block}
      .qr figcaption{font-size:.78rem;color:var(--muted);margin-top:6px}
      .warn{color:var(--amber);font-size:.78rem;margin-top:12px}
      dialog{background:var(--surface);color:var(--ink);border:1px solid var(--rule);
        border-radius:10px;padding:20px;max-width:min(94vw,560px)}
      dialog::backdrop{background:rgba(0,0,0,.6)}
      .empty{color:var(--muted);font-size:.9rem}
      .err{color:var(--red);font-size:.85rem}
    </style>
    </head>
    <body>
    <main>
      <h1>Beltpack Host</h1>

      <section id="gate" class="card" hidden>
        <h2>Sign in</h2>
        <label>Admin passcode
          <input id="pass" type="password" autocomplete="current-password">
        </label>
        <div class="row"><button id="signin">Unlock</button><span id="gate-err" class="err"></span></div>
      </section>

      <div id="panel" hidden style="display:flex;flex-direction:column;gap:22px">
        <section class="card">
          <div class="row">
            <span id="lamp" class="lamp"></span>
            <div class="grow">
              <div id="state" class="state">Loading…</div>
              <div id="detail" class="sub"></div>
            </div>
            <button id="pair" class="ghost">Pair</button>
            <button id="toggle">Start</button>
          </div>
        </section>

        <section class="card">
          <h2>Audio devices</h2>
          <label>Console in <select id="input"></select></label>
          <label>Channel <input id="inputChannel" type="number" min="1" placeholder="first"></label>
          <label>Return out <select id="output"></select></label>
          <label>Channel <input id="outputChannel" type="number" min="1" placeholder="first"></label>
          <div class="sub">Blank takes whatever the device offers first, which is right for an
            ordinary interface. A console needs the channel it actually carries comms on.
            Changing this restarts the bridge.</div>
          <div id="chanerr" class="err"></div>
          <div id="mic" class="sub"></div>
        </section>

        <section class="card">
          <h2>Talking</h2>
          <label class="row"><input id="canpublish" type="checkbox"> Phones may talk</label>
          <div class="sub">Off makes every beltpack listen-only. Applies when a phone next
            joins — anyone already on comms keeps what they were given.</div>
          <div id="puberr" class="err"></div>
        </section>

        <section class="card">
          <h2>On comms</h2>
          <ul id="people"></ul>
          <div id="nobody" class="empty">Nobody connected.</div>
        </section>
      </div>
    </main>

    <dialog id="pairdlg">
      <h2>Pair a beltpack</h2>
      <div id="qr" class="qr"></div>
      <p class="warn">These codes contain the join passcode. Anyone who photographs one is on comms.</p>
      <div class="row" style="justify-content:flex-end"><button id="closepair" class="ghost">Done</button></div>
    </dialog>

    <script>
    const $ = (id) => document.getElementById(id);
    const KEY = "beltpack.admin";
    let pass = sessionStorage.getItem(KEY) || "";
    let busy = false;

    async function api(path, options = {}) {
      const res = await fetch(path, {
        ...options,
        headers: { ...(options.headers || {}), "X-Beltpack-Admin": pass },
      });
      if (res.status === 401) { lock("That passcode was rejected."); throw new Error("unauthorised"); }
      if (!res.ok) {
        // Refusals explain themselves in the body. Without this the page would
        // show "400" and throw away the sentence that says what to do about it.
        let detail = `${res.status}`;
        try { const body = await res.json(); if (body && body.error) detail = body.error; } catch { /* not JSON */ }
        throw new Error(detail);
      }
      return res.json();
    }

    function lock(message) {
      pass = "";
      sessionStorage.removeItem(KEY);
      $("gate").hidden = false;
      $("panel").hidden = true;
      $("gate-err").textContent = message || "";
    }

    function unlock() {
      $("gate").hidden = true;
      $("panel").hidden = false;
    }

    function fillDevices(select, devices) {
      // Rebuilding while open would fight the operator mid-choice.
      if (document.activeElement === select) return;
      select.innerHTML = "";
      for (const d of devices) {
        const option = document.createElement("option");
        option.value = d.uid;
        option.textContent = `${d.name}  ·  ${d.channels} ch`;
        option.selected = d.selected;
        select.append(option);
      }
    }

    // Never rewrite a field the operator is currently typing into.
    function setField(id, value) {
      const el = $(id);
      if (document.activeElement === el) return;
      el.value = value === null || value === undefined ? "" : value;
    }

    function render(s) {
      $("lamp").dataset.s = s.state;
      $("state").textContent = {
        running: "On air", stopped: "Stopped", starting: "Starting…",
        reconnecting: "Reconnecting…", failed: "Failed",
      }[s.state] || s.state;
      $("detail").textContent = s.message || (s.room ? `Room "${s.room}" at ${s.url}` : "");

      const running = s.state === "running";
      const toggle = $("toggle");
      toggle.textContent = running ? "Stop" : "Start";
      toggle.className = running ? "stop" : "";
      toggle.disabled = busy || s.state === "starting";
      $("pair").disabled = !s.canPair;

      fillDevices($("input"), s.inputs);
      fillDevices($("output"), s.outputs);
      setField("inputChannel", s.inputChannel);
      setField("outputChannel", s.outputChannel);
      // The device's own count, so a channel that cannot exist is refused by
      // the field rather than by the audio unit an hour later.
      $("inputChannel").max = s.inputChannelMax ?? "";
      $("outputChannel").max = s.outputChannelMax ?? "";
      $("inputChannel").placeholder = s.inputChannelMax ? `first of ${s.inputChannelMax}` : "first";
      $("outputChannel").placeholder = s.outputChannelMax ? `first of ${s.outputChannelMax}` : "first";
      if (document.activeElement !== $("canpublish")) $("canpublish").checked = s.canPublish;
      $("mic").textContent = `Microphone access: ${s.micStatus}`;

      const people = $("people");
      people.innerHTML = "";
      for (const p of s.participants) {
        const li = document.createElement("li");
        const dot = document.createElement("span");
        dot.className = "dot";
        dot.dataset.speaking = String(p.isSpeaking);
        const name = document.createElement("span");
        name.textContent = p.name;
        li.append(dot, name);
        if (p.isBridge) {
          const tag = document.createElement("span");
          tag.className = "tag";
          tag.textContent = "CONSOLE";
          li.append(tag);
        }
        const mic = document.createElement("span");
        mic.className = "mic";
        mic.dataset.live = String(p.publishesAudio && !p.isMuted);
        mic.textContent = !p.publishesAudio ? "listening" : p.isMuted ? "muted" : "live";
        li.append(mic);
        people.append(li);
      }
      $("nobody").hidden = s.participants.length > 0;
    }

    async function refresh() {
      if (!pass) return;
      try { render(await api("/admin/status")); } catch { /* handled in api */ }
    }

    $("signin").onclick = async () => {
      pass = $("pass").value;
      try {
        const s = await api("/admin/status");
        sessionStorage.setItem(KEY, pass);
        unlock();
        render(s);
      } catch { /* lock() already ran */ }
    };
    $("pass").onkeydown = (e) => { if (e.key === "Enter") $("signin").click(); };

    $("toggle").onclick = async () => {
      busy = true;
      $("toggle").disabled = true;
      const running = $("toggle").textContent === "Stop";
      try { render(await api(running ? "/admin/stop" : "/admin/start", { method: "POST" })); }
      finally { busy = false; }
    };

    for (const which of ["input", "output"]) {
      $(which).onchange = async () => {
        const body = JSON.stringify({ [which]: $(which).value });
        render(await api("/admin/devices", {
          method: "POST", headers: { "content-type": "application/json" }, body,
        }));
      };
    }

    // Both channels go up together: the server cannot tell an explicit null
    // from a missing key, so "leave the other one alone" has to be said out
    // loud by sending its current value.
    function channelValue(id) {
      const raw = $(id).value.trim();
      if (raw === "") return null;
      const n = Number(raw);
      return Number.isInteger(n) && n >= 1 ? n : null;
    }

    for (const which of ["inputChannel", "outputChannel"]) {
      $(which).onchange = async () => {
        $("chanerr").textContent = "";
        const body = JSON.stringify({
          input: channelValue("inputChannel"),
          output: channelValue("outputChannel"),
        });
        try {
          render(await api("/admin/channels", {
            method: "POST", headers: { "content-type": "application/json" }, body,
          }));
        } catch (e) {
          $("chanerr").textContent = e.message;
          refresh();
        }
      };
    }

    $("canpublish").onchange = async () => {
      $("puberr").textContent = "";
      const body = JSON.stringify({ allowed: $("canpublish").checked });
      try {
        render(await api("/admin/publish", {
          method: "POST", headers: { "content-type": "application/json" }, body,
        }));
      } catch (e) {
        $("puberr").textContent = e.message;
        refresh();
      }
    };

    $("pair").onclick = async () => {
      const p = await api("/admin/pair");
      $("qr").innerHTML = "";
      for (const [label, svg, url] of [
        ["iPhone — opens the app", p.appSVG, p.appURL],
        ["Android — opens in a browser", p.webSVG, p.webURL],
      ]) {
        if (!svg) continue;
        const fig = document.createElement("figure");
        fig.innerHTML = svg;
        const cap = document.createElement("figcaption");
        cap.textContent = label;
        fig.append(cap);
        fig.title = url || "";
        $("qr").append(fig);
      }
      $("pairdlg").showModal();
    };
    $("closepair").onclick = () => $("pairdlg").close();

    if (pass) { unlock(); refresh(); } else { lock(); }
    setInterval(refresh, 1500);
    </script>
    </body>
    </html>
    """#
}

#endif
