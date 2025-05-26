// Changelogs Module
(function() {
  'use strict';



  // Function to render changelogs
  function renderChangelogs(posts) {
    const list = document.getElementById('changelog-list');
    if (!list) return;
    list.innerHTML = posts.length
      ? posts.map(renderChangelogCard).join('')
      : '<div class="text-white text-center">No changelogs found.</div>';
    
    // Re-attach toggle logic for dropdowns
    document.querySelectorAll('.changelog-toggle').forEach(button => {
      const panel = document.querySelector(`[data-panel="${button.dataset.target}"]`);
      const arrow = button.querySelector('.arrow-icon');
      button.addEventListener('click', () => {
        const isOpen = panel.style.maxHeight && panel.style.maxHeight !== '0px';
        if (isOpen) {
          panel.style.maxHeight = '0px';
          arrow.classList.remove('rotate-180');
        } else {
          panel.style.maxHeight = panel.scrollHeight + 'px';
          arrow.classList.add('rotate-180');
        }
      });
    });
    
    document.querySelectorAll('.changelog-panel').forEach(panel => {
      panel.style.maxHeight = '0px';
    });
  }

  // Helper function to capitalize first letter
  function capitalize(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  // Format date function
  function formatDate(dateStr) {
    const dateObj = new Date(dateStr);
    if (isNaN(dateObj)) return dateStr;
    return `${dateObj.getDate()} ${dateObj.toLocaleString('default', { month: 'long' })} ${dateObj.getFullYear()}`;
  }

  // Function to scroll to a specific changelog based on URL hash
  function scrollToChangelog() {
    const hash = window.location.hash;
    if (!hash) return;
    
    const deploymentId = hash.substring(1);
    if (!deploymentId) return;
    
    const targetCard = document.querySelector(`[data-deployment-id="${deploymentId}"]`);
    if (!targetCard) return;
    
    targetCard.scrollIntoView({ behavior: 'smooth', block: 'start' });
    
    // Add highlight effect
    targetCard.classList.add('highlight-changelog');
    setTimeout(() => {
      targetCard.classList.remove('highlight-changelog');
    }, 3000);
  }

  // Render a single changelog card
  function renderChangelogCard(post) {
    return `
      <div class="relative rounded-2xl shadow-lg max-w-2xl w-full mb-8 overflow-hidden bg-[#111122] changelog-card" 
           data-deployment-id="${post.deploymentId || ''}">
        <img src="${post.thumbnail || '/images/default-changelog.png'}" alt="Changelog Card" class="w-full h-auto object-cover min-h-[220px]" />
        <div class="absolute top-0 left-0 flex gap-2 p-4 z-10">
          ${(post.tags || []).map(tag => `<span class="px-2 py-0.5 rounded-full text-xs font-normal" style="background-color: ${tag.color || '#6366f1'}; color: #fff;">${tag.name}</span>`).join('')}
        </div>
        <div class="absolute top-0 right-0 flex gap-2 p-4 z-10">
          <span class="bg-[#111122] text-xs text-white font-bold px-2 py-1 rounded-full flex items-center gap-1">
            <img src="/images/${post.flavor || 'release'}.png" alt="${post.flavor || 'Release'}" class="h-4 w-4 object-contain" /> ${capitalize(post.flavor || 'Release')}
          </span>
        </div>
        <div class="relative z-10 p-8 pt-6 bg-[#111122] bg-opacity-95 rounded-b-2xl">
          <div class="text-white text-xl font-bold mb-2">${post.title}</div>
          <div class="text-gray-400 text-sm mb-4">v${post.version} | ${formatDate(post.createdAt)}</div>
          <div class="text-gray-200 mb-4">${post.summary}</div>
          ${renderDropdowns(post.dropdowns)}
          <div class="text-gray-400 text-xs mb-2">Contributors: ${post.content || 'Unknown'}</div>
        </div>
      </div>`;
  }

// Render dropdowns for changelog entries
function renderDropdowns(dropdowns) {
  if (!dropdowns || !dropdowns.length) return '';
  const md = window.markdownit ? window.markdownit() : null;
  
  return dropdowns.map(drop => {
    let markdownContent = '';
    if (Array.isArray(drop.content)) {
      markdownContent = drop.content.map(item => (md ? md.render(item) : `<li>${item}</li>`)).join('');
    } else if (typeof drop.content === 'string') {
      markdownContent = md ? md.render(drop.content) : `<li>${drop.content}</li>`;
    } else if (drop.content && typeof drop.content === 'object') {
      markdownContent = md ? md.render(JSON.stringify(drop.content)) : `<li>${JSON.stringify(drop.content)}</li>`;
    } else {
      markdownContent = md ? md.render('No details provided.') : '<li>No details provided.</li>';
    }
    
    return `
      <div class="mb-4 p-3 bg-[#19192c] rounded-xl">
        <button class="changelog-toggle w-full text-white font-semibold mb-1 cursor-pointer focus:outline-none flex items-center justify-between" data-target="${drop.title}">
          <span class="flex items-center gap-2">
            <img class="w-4 h-4 text-white" src="/images/${drop.icon}.png"/>
            ${drop.title}
          </span>
          <svg class="arrow-icon w-4 h-4 ml-2 transition-transform duration-300 transform" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" /></svg>
        </button>
        <div class="changelog-panel overflow-hidden transition-all duration-300 ease-in-out max-h-96" data-panel="${drop.title}">
          <div class="dropdown-markdown markdown-body text-white">${markdownContent}</div>
        </div>
      </div>
    `;
  }).join('');
}

// Platform/Channel Selector Logic
const channelBtnIds = ['changelog-btn-all', 'changelog-btn-release', 'changelog-btn-beta', 'changelog-btn-nightly'];
const channelKeyMap = {
  'changelog-btn-all': 'all',
  'changelog-btn-release': 'release',
  'changelog-btn-beta': 'beta',
  'changelog-btn-nightly': 'nightly'
};
let currentChannel = 'all';

// Update active button styling
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

// Fetch and render changelogs by channel
function fetchAndRenderChangelogsByChannel({ revertOnFail = true, prevChannel = 'all' } = {}) {
  if (typeof window.allChangelogs === 'object' && Array.isArray(window.allChangelogs)) {
    // Enable/disable channel buttons based on data
    channelBtnIds.forEach(id => {
      const btn = document.getElementById(id);
      if (!btn) return;
      const key = channelKeyMap[id];
      const hasAny = (key === 'all')
        ? window.allChangelogs.length > 0
        : window.allChangelogs.some(post => (post.flavor || 'release').toLowerCase() === key);
      
      btn.disabled = !hasAny;
      btn.classList.toggle('disabled-btn', !hasAny);
      btn.setAttribute('aria-disabled', !hasAny ? 'true' : 'false');
    });
    
    // Filter changelogs based on selected channel
    let filtered = window.allChangelogs;
    if (currentChannel !== 'all') {
      filtered = filtered.filter(post => (post.flavor || 'release').toLowerCase() === currentChannel);
    }
    
    renderChangelogs(filtered);
    updateActiveButton(channelBtnIds, channelBtnIds.find(id => channelKeyMap[id] === currentChannel));
  } else if (revertOnFail) {
    currentChannel = prevChannel;
    updateActiveButton(channelBtnIds, channelBtnIds.find(id => channelKeyMap[id] === prevChannel));
  }
}

// Initialize changelogs functionality
function initializeChangelogs() {
  // Add highlight styles
  const style = document.createElement('style');
  style.textContent = `
    .changelog-card {
      transition: box-shadow 0.3s ease;
    }
    .highlight-changelog {
      box-shadow: 0 0 0 3px #64009E, 0 0 20px rgba(100, 0, 158, 0.5) !important;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(100, 0, 158, 0.7); }
      70% { box-shadow: 0 0 0 10px rgba(100, 0, 158, 0); }
      100% { box-shadow: 0 0 0 0 rgba(100, 0, 158, 0); }
    }
  `;
  document.head.appendChild(style);

  // Setup channel selector buttons
  channelBtnIds.forEach(id => {
    const btn = document.getElementById(id);
    if (!btn) return;
    
    btn.addEventListener('click', () => {
      if (btn.disabled) return;
      const prevChannel = currentChannel;
      currentChannel = channelKeyMap[id];
      fetchAndRenderChangelogsByChannel({ revertOnFail: true, prevChannel });
    });
  });
  
  // Initial fetch and render
  const list = document.getElementById('changelog-list');
  fetch('/api/posts?type=changelog')
    .then(res => res.json())
    .then(data => {
      window.allChangelogs = data.posts || [];
      fetchAndRenderChangelogsByChannel({ revertOnFail: false });
      
      if (!list) return;
      list.innerHTML = window.allChangelogs.length
        ? window.allChangelogs.map(renderChangelogCard).join('')
        : '<div class="text-white text-center">No changelogs found.</div>';
      
      // Re-attach toggle logic
      document.querySelectorAll('.changelog-toggle').forEach(button => {
        const panel = document.querySelector(`[data-panel="${button.dataset.target}"]`);
        const arrow = button.querySelector('.arrow-icon');
        button.addEventListener('click', () => {
          const isOpen = panel.style.maxHeight && panel.style.maxHeight !== '0px';
          if (isOpen) {
            panel.style.maxHeight = '0px';
            arrow.classList.remove('rotate-180');
          } else {
            panel.style.maxHeight = panel.scrollHeight + 'px';
            arrow.classList.add('rotate-180');
          }
        });
      });
      
      document.querySelectorAll('.changelog-panel').forEach(panel => {
        panel.style.maxHeight = '0px';
      });

      // Scroll to changelog if hash exists
      setTimeout(scrollToChangelog, 100);
    })
    .catch(error => {
      console.error('Error loading changelogs:', error);
      if (list) {
        list.innerHTML = '<div class="text-white text-center">Error loading changelogs. Please try again later.</div>';
      }
    });

  // Initial check in case the page loads with a hash
  if (window.location.hash) {
    // Small delay to ensure the page has loaded
    setTimeout(scrollToChangelog, 100);
  }
}

  // Export the public API
  const changelogsModule = {
    initializeChangelogs,
    renderChangelogs,
    fetchAndRenderChangelogsByChannel,
    scrollToChangelog
  };

  // Expose to global scope
  window.changelogsModule = changelogsModule;

  // Auto-initialize if we're not in an SPA context
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      const isInSPA = document.querySelector('meta[name="spa"]') !== null;
      if (!isInSPA) {
        initializeChangelogs();
      }
    });
  } else if (!document.querySelector('meta[name="spa"]')) {
    // If DOM is already loaded and not in SPA
    initializeChangelogs();
  }

  // Export for CommonJS/Node.js
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = changelogsModule;
  }
})();
