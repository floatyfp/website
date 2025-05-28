const platformBtnIds = ['platform-windows', 'platform-macos', 'platform-linux', 'platform-android', 'platform-ios'];
const channelBtnIds2 = ['release-btn', 'beta-btn', 'nightly-btn'];
let currentPlatform = 'windows';
let currentChannel2 = 'release';
let lastValidPlatform = currentPlatform;
let lastValidChannel = currentChannel2;

// Platform detection and hash preselect
function detectPlatform() {
  // 1. Check hash`
  const hash = window.location.hash.toLowerCase().replace('#', '');
  const validPlatforms = ['windows','macos','linux','android','ios'];
  if (validPlatforms.includes(hash)) {
    return hash;
  }
  // 2. Auto-detect
  // Prefer UA Data API if available (modern browsers)
  if (navigator.userAgentData && navigator.userAgentData.platform) {
    const plat = navigator.userAgentData.platform.toLowerCase();
    if (plat.includes('android')) return 'android';
    if (plat.includes('iphone') || plat.includes('ipad') || plat.includes('ipod') || plat.includes('ios')) return 'ios';
    if (plat.includes('win')) return 'windows';
    if (plat.includes('mac')) return 'macos';
    if (plat.includes('chrome os')) return 'chromeos';
    if (plat.includes('linux')) return 'linux';
  }
  // Fallback: classic UA string
  const ua = navigator.userAgent;
  if (/android/i.test(ua)) return 'android';
  if (/iphone|ipad|ipod/i.test(ua)) return 'ios';
  if (/cros/i.test(ua)) return 'chromeos';
  if (/windows/i.test(ua)) return 'windows';
  if (/macintosh|mac os x/i.test(ua)) return 'macos';
  if (/linux/i.test(ua) && !/android/i.test(ua)) return 'linux';
  return 'windows';
}

function detectChannelandSetButton() {
  const hash = detectPlatform();
  const urlParams = new URLSearchParams(window.location.search);
  const flavor = urlParams.get('f');
  updateActiveButton(platformBtnIds, 'platform-' + hash);
  if (!flavor) return hash;
  updateActiveButton(channelBtnIds2, flavor + '-btn');
  return hash;
}

currentPlatform = detectChannelandSetButton();
lastValidPlatform = currentPlatform;

// Map platform button IDs to API keys
const platformKeyMap = {
  'platform-windows': 'windows',
  'platform-macos': 'macos',
  'platform-linux': 'linux',
  'platform-android': 'android',
  'platform-ios': 'ios',
};

// Map channel button IDs to channel keys
const channelKeyMap2 = {
  'release-btn': 'release',
  'beta-btn': 'beta',
  'nightly-btn': 'nightly',
};

function updateActiveButton(btnIds, activeId) {
  btnIds.forEach(id => {
    const btn = document.getElementById(id);
    if (!btn) return;
    if (id === activeId) {
      btn.classList.remove('text-white/80');
      btn.classList.add('bg-[#64009E]', 'text-white', 'active');
      btn.setAttribute('aria-pressed', 'true');
    } else {
      btn.classList.remove('bg-[#64009E]', 'text-white', 'active');
      btn.classList.add('text-white/80');
      btn.setAttribute('aria-pressed', 'false');
    }
  });
}

platformBtnIds.forEach(id => {
  const btn = document.getElementById(id);
  if (!btn) return;
  btn.addEventListener('click', () => {
    if (btn.disabled) return;
    const prevPlatform = currentPlatform;
    currentPlatform = platformKeyMap[id];
    updateActiveButton(platformBtnIds, id);
    fetchAndRenderDeployment({
      revertOnFail: true,
      prevPlatform
    });
  });
});

channelBtnIds2.forEach(id => {
  const btn = document.getElementById(id);
  if (!btn) return;
  btn.addEventListener('click', () => {
    if (btn.disabled) return;
    const prevChannel = currentChannel2;
    currentChannel2 = channelKeyMap2[id];
    updateActiveButton(channelBtnIds2, id);
    fetchAndRenderDeployment({
      revertOnFail: true,
      prevChannel
    });
  });
});

let used = false;

function getFlavor() {
  used = true;
  const urlParams = new URLSearchParams(window.location.search);
  return used ? null : urlParams.get('f');
}

// Fetch latest visible deployment for the selected platform/channel
async function fetchAndRenderDeployment(options = {}) {
  // Support ?v=version query parameter
  const urlParams = new URLSearchParams(window.location.search);
  const version = urlParams.get('v');
  const flavor = getFlavor();
  let apiUrl = `/api/deployments?platform=${encodeURIComponent(currentPlatform)}&channel=${encodeURIComponent(flavor ? flavor : currentChannel2)}&visible=1&limit=1`;
  if (version) {
    apiUrl += `&version=${encodeURIComponent(version)}`;
  }
  if (flavor) {
    apiUrl += `&flavor=${encodeURIComponent(flavor)}`;
  }
  try {
    const res = await fetch(apiUrl);
    if (!res.ok) throw new Error('Failed to fetch deployment');
    const data = await res.json();
    if (!data.deployments || !data.deployments.length) {
      // No deployment found for this selection
      renderNoDeployment();
      // Disable the current selector button
      // Revert to previous valid selection
      if (options.revertOnFail) {
        // Platform change
        if (options.prevPlatform && options.prevPlatform !== currentPlatform) {
          // Disable the current platform button
          const btnId = Object.keys(platformKeyMap).find(key => platformKeyMap[key] === currentPlatform);
          if (btnId) {
            const btn = document.getElementById(btnId);
            if (btn) btn.disabled = true;
          }
          currentPlatform = options.prevPlatform;
          updateActiveButton(platformBtnIds, Object.keys(platformKeyMap).find(key => platformKeyMap[key] === currentPlatform));
        }
        // Channel change
        if (options.prevChannel && options.prevChannel !== currentChannel2) {
          const btnId = Object.keys(channelKeyMap2).find(key => channelKeyMap2[key] === currentChannel2);
          if (btnId) {
            const btn = document.getElementById(btnId);
            if (btn) btn.disabled = true;
          }
          currentChannel2 = options.prevChannel;
          updateActiveButton(channelBtnIds2, Object.keys(channelKeyMap2).find(key => channelKeyMap2[key] === currentChannel2));
        }
        // Re-fetch with reverted selection
        fetchAndRenderDeployment();
      }
      return;
    }
    // Found a deployment, remember this as the last valid
    lastValidPlatform = currentPlatform;
    lastValidChannel = currentChannel2;

    renderDeployment(data.deployments[0]);
  } catch (e) {
    renderNoDeployment();
  }
}

function renderDeployment(deployment) {
  // Update the card with deployment info
  const card = document.getElementById('download-card');
  if (!card) return;
  // Title
  const titleDiv = card.querySelector('.download-title');
  if (titleDiv) titleDiv.innerHTML = `<img src="/images/${currentPlatform}.png" alt="${capitalize(currentPlatform)}" class="w-6 h-6 object-contain" /> ${capitalize(currentPlatform)} Download`;
  // Set logo background image based on flavor
  const logoDiv = card.querySelector('[aria-label="Floaty logo"]');
  if (logoDiv) {
    const flavor = deployment.flavor || 'release';
    logoDiv.style.backgroundImage = `url('/images/${flavor}-icon.png')`;
    logoDiv.style.backgroundSize = 'cover';
    logoDiv.style.backgroundPosition = 'center';
    logoDiv.style.backgroundRepeat = 'no-repeat';
  }
  // Info
  const infoDiv = card.querySelector('.download-info');
  if (infoDiv) infoDiv.innerHTML = `${capitalize(deployment.flavor)} Version <b>${deployment.version}</b> &bull; ${deployment.date ? new Date(deployment.date).toLocaleDateString() : ''}<br>${deployment.changelog ? `<a href='${deployment.changelog}' class='text-[#64009E] underline' target='_blank'>View Changelog</a>` : `<a class='text-yellow-400'>You are viewing an old version!</a>`}`;
  // Generate buttons dynamically based on deployment.files
  const btnContainer = card.querySelector('.flex.flex-col.gap-2');
  btnContainer.innerHTML = '';
  // Use deployment.files directly (already filtered by platform)
  let files = Array.isArray(deployment.files) ? deployment.files : [];
  if (files.length === 0) {
    btnContainer.innerHTML = '<div class="text-gray-400">No downloads available for this platform.</div>';
    return;
  }
  files.forEach(file => {
    const btn = document.createElement('button');
    btn.className = 'bg-[#29204a] text-white rounded-lg px-5 py-2 mt-2 font-semibold border-none transition-colors duration-200 flex items-center gap-2 hover:bg-[#64009E] download-btn';
    btn.innerHTML = `<img src="/images/downloadicon.png" alt="Download" class="w-6 h-6 object-contain" /> ${file.name || file.type || 'Download'}`;
    btn.onclick = () => window.open('/download/media/' + file.path, '_blank');
    btnContainer.appendChild(btn);
  });
}

function renderNoDeployment() {
  const card = document.getElementById('download-card');
  if (!card) return;
  const titleDiv = card.querySelector('.download-title');
  if (titleDiv) titleDiv.innerHTML = `<span style=\"font-size:1.5rem;\">&#x26A0;</span> No Download Available`;
  const infoDiv = card.querySelector('.download-info');
  if (infoDiv) infoDiv.innerHTML = 'No deployment found for this platform/channel.';
  const btns = card.querySelectorAll('.download-btn');
  btns.forEach(btn => { btn.disabled = true; });
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// Matrix of available deployments for [platform][channel]
let platformChannelMatrix = null;

async function fetchMatrixAndInit() {
  try {
    const res = await fetch('/api/platform-channel-matrix');
    if (!res.ok) throw new Error('Failed to fetch matrix');
    const data = await res.json();
    platformChannelMatrix = data.matrix;
    // Only disable a platform button if ALL channels are unavailable for that platform
    platformBtnIds.forEach(id => {
      const plat = platformKeyMap[id];
      const hasAny = platformChannelMatrix && platformChannelMatrix[plat] && Object.values(platformChannelMatrix[plat]).some(Boolean);
      const btn = document.getElementById(id);
      if (btn) btn.disabled = !hasAny;
    });
    // Disable unavailable channel buttons for the current platform
    channelBtnIds2.forEach(id => {
      const chan = channelKeyMap2[id];
      const plat = currentPlatform;
      const btn = document.getElementById(id);
      if (btn) btn.disabled = !(platformChannelMatrix && platformChannelMatrix[plat] && platformChannelMatrix[plat][chan]);
    });
    // If current selection is unavailable, pick the first available
    if (!platformChannelMatrix[currentPlatform] || !Object.values(platformChannelMatrix[currentPlatform]).some(Boolean)) {
      // Pick first platform with any deployment
      for (const plat of Object.keys(platformChannelMatrix)) {
        if (Object.values(platformChannelMatrix[plat]).some(Boolean)) {
          currentPlatform = plat;
          break;
        }
      }
      updateActiveButton(platformBtnIds, Object.keys(platformKeyMap).find(key => platformKeyMap[key] === currentPlatform));
    }
    if (!platformChannelMatrix[currentPlatform][currentChannel2]) {
      // Pick first available channel for this platform
      for (const chan of Object.keys(platformChannelMatrix[currentPlatform])) {
        if (platformChannelMatrix[currentPlatform][chan]) {
          currentChannel2 = chan;
          break;
        }
      }
      updateActiveButton(channelBtnIds2, Object.keys(channelKeyMap2).find(key => channelKeyMap2[key] === currentChannel2));
    }
    fetchAndRenderDeployment();
  } catch (e) {
    // fallback: just fetch deployment as before
    fetchAndRenderDeployment();
  }
}

// Initial load
fetchMatrixAndInit();
