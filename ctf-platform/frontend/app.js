const API_BASE = "http://localhost:8000";

function setToken(token) {
  localStorage.setItem("token", token);
}

function getToken() {
  return localStorage.getItem("token");
}

function logout() {
  localStorage.removeItem("token");
  window.location.href = "login.html";
}

async function api(path, options = {}) {
  const headers = options.headers || {};
  const token = getToken();
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  const resp = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(text || resp.statusText);
  }
  return resp.json();
}

function setupAuthForms() {
  const loginForm = document.getElementById("login-form");
  const registerForm = document.getElementById("register-form");
  const status = document.getElementById("status");

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(loginForm));
    try {
      const resp = await api("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      setToken(resp.access_token);
      window.location.href = "dashboard.html";
    } catch (err) {
      status.textContent = `Login failed: ${err.message}`;
    }
  });

  registerForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(registerForm));
    try {
      const resp = await api("/api/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      setToken(resp.access_token);
      window.location.href = "dashboard.html";
    } catch (err) {
      status.textContent = `Register failed: ${err.message}`;
    }
  });
}

async function loadDashboard() {
  try {
    const challenges = await api("/api/challenges");
    const instances = await api("/api/instances");
    renderChallenges(challenges);
    renderInstances(instances);
  } catch (err) {
    alert(`Failed to load dashboard: ${err.message}`);
  }
}

function renderChallenges(items) {
  const container = document.getElementById("challenges");
  container.innerHTML = "";
  items.forEach((item) => {
    const div = document.createElement("div");
    div.className = "card";
    div.innerHTML = `
      <h3>${item.id}: ${item.name}</h3>
      <p>${item.description}</p>
      <p><strong>Categories:</strong> ${item.categories.join(", ")}</p>
      <button class="button" onclick="startInstance('${item.id}')">Start</button>
    `;
    container.appendChild(div);
  });
}

function renderInstances(items) {
  const container = document.getElementById("instances");
  container.innerHTML = "";
  items.forEach((item) => {
    const div = document.createElement("div");
    div.className = "card";
    const ssh = item.ssh_port
      ? `ssh -p ${item.ssh_port} ctf@${item.ssh_host}`
      : "starting...";
    div.innerHTML = `
      <h3>${item.challenge_id}</h3>
      <p>Status: ${item.status}</p>
      <p>SSH: <code>${ssh}</code></p>
      <button class="button" onclick="openTerminal('${item.id}')">Browser Terminal</button>
      <button class="button secondary" onclick="stopInstance('${item.id}')">Stop</button>
    `;
    container.appendChild(div);
  });
}

async function startInstance(challengeId) {
  await api("/api/instances/start", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ challenge_id: challengeId }),
  });
  loadDashboard();
}

async function stopInstance(instanceId) {
  await api(`/api/instances/stop?instance_id=${instanceId}`, { method: "POST" });
  loadDashboard();
}

async function submitFlag() {
  const challengeId = document.getElementById("flag-challenge").value;
  const flagValue = document.getElementById("flag-value").value;
  const status = document.getElementById("flag-status");
  try {
    const resp = await api("/api/submit", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ challenge_id: challengeId, flag: flagValue }),
    });
    status.textContent = resp.correct ? "Correct!" : "Incorrect.";
  } catch (err) {
    status.textContent = `Submit failed: ${err.message}`;
  }
}

async function saveKey() {
  const publicKey = document.getElementById("public-key").value;
  await api("/api/profile/key", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ public_key: publicKey }),
  });
  alert("Key saved.");
}

function openTerminal(instanceId) {
  window.location.href = `terminal.html?instance=${instanceId}`;
}

function startTerminal() {
  const params = new URLSearchParams(window.location.search);
  const instanceId = params.get("instance");
  const token = getToken();
  if (!instanceId || !token) {
    alert("Missing instance or auth.");
    return;
  }

  const term = new window.Terminal({
    cursorBlink: true,
    fontFamily: "Fira Mono, monospace",
  });
  term.open(document.getElementById("terminal"));

  const ws = new WebSocket(`ws://localhost:8000/ws/terminal/${instanceId}?token=${token}`);
  ws.binaryType = "arraybuffer";

  ws.onmessage = (event) => {
    if (event.data instanceof ArrayBuffer) {
      term.write(new Uint8Array(event.data));
    } else {
      term.write(event.data);
    }
  };

  term.onData((data) => {
    ws.send(data);
  });
}
