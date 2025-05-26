// SPA Router for Floaty
document.addEventListener('DOMContentLoaded', initRouter);

// Metadata cache
const metadataCache = {};

// Page content cache
const pageCache = {
  home: null,
  blog: null,
  download: null,
  post: null,
  changelogs: null
};

// Page scripts cache
const scriptCache = {};

// Current route data
let currentRoute = {
  page: 'home',
  params: {}
};

// Page specific initialization functions
const pageInitializers = {
  home: initHomePage,
  blog: initBlogPage,
  download: initDownloadPage,
  post: initPostPage,
  changelogs: initChangelogsPage
};

// Initialize the router
async function initRouter() {
  // Load navbar
  await loadNavbar();
  
  // Load footer
  await loadFooter();
  
  // Setup event listeners for navigation
  setupNavigationListeners();
  
  // Handle initial route
  handleRouteChange();
  
  // Listen for popstate events (browser back/forward)
  window.addEventListener('popstate', handleRouteChange);
}

// Load the navbar content
async function loadNavbar() {
  try {
    const response = await fetch('/navbar.html');
    const data = await response.text();
    document.getElementById('navbar-placeholder').innerHTML = data;
    
    // Load navbar.js script
    const script = document.createElement('script');
    script.src = '/navbar.js';
    document.body.appendChild(script);
  } catch (error) {
    console.error('Failed to load navbar:', error);
  }
}

// Load the footer content
async function loadFooter() {
  try {
    const response = await fetch('/footer.html');
    const html = await response.text();
    document.getElementById('footer-container').innerHTML = html;
  } catch (error) {
    console.error('Failed to load footer:', error);
  }
}

// Set up event listeners for navigation links
function setupNavigationListeners() {
  // Use event delegation to handle all navigation clicks
  document.body.addEventListener('click', (event) => {
    // Find the closest anchor tag
    const link = event.target.closest('a');
    if (!link) return;
    
    const href = link.getAttribute('href');
    
    // Skip external links, anchor links, or links with special behaviors
    if (!href || 
        href.startsWith('http') || 
        href.startsWith('//') || 
        href.startsWith('#') || 
        href.includes('editor') || 
        href.includes('error') || 
        href.includes('deploy_test')) {
      return;
    }
    
    // Prevent default behavior
    event.preventDefault();
    
    // Navigate to the page
    navigateTo(href);
  });
}

// Navigate to a specific route
function navigateTo(url) {
  // Check if we need to reload when navigating to blog from home
  const isNavigatingToBlog = url === '/blog' || url.startsWith('/blog/');
  const shouldReload = isNavigatingToBlog && navigationState.hasVisitedHome && 
                     navigationState.currentPage === 'home' && 
                     navigationState.lastReloaded !== 'blog';
  
  if (shouldReload) {
    // Set flag to prevent infinite reloads
    navigationState.lastReloaded = 'blog';
    window.location.href = url;
    return;
  }
  
  // Update browser history
  window.history.pushState({}, '', url);
  
  // Handle the route change
  handleRouteChange();
}

// Handle route changes
async function handleRouteChange() {
  // Parse the current URL
  const path = window.location.pathname;
  
  // Determine which page to show
  let page = 'home';
  const params = {};
  
  if (path === '/') {
    page = 'home';
  } else if (path === '/blog') {
    page = 'blog';
  } else if (path === '/download') {
    page = 'download';
  } else if (path === '/changelogs') {
    page = 'changelogs';
  } else if (path.startsWith('/post/')) {
    page = 'post';
    params.slug = path.substring('/post/'.length);
  }
  
  // Update current route
  currentRoute = { page, params };
  
  // Clear existing metadata
  clearMetadata();
  
  // Show the selected page
  await showPage(page, params);
}

// Show a specific page
async function showPage(page, params = {}) {
  // Update navigation state
  if (page === 'home') {
    navigationState.hasVisitedHome = true;
    sessionStorage.setItem('hasVisitedHome', 'true');
  }
  navigationState.currentPage = page;
  
  // Hide all pages
  document.querySelectorAll('.page').forEach(el => {
    el.classList.remove('active');
  });
  
  // Toggle changelog background
  const changelogBg = document.querySelector('.changelog-bg');
  if (changelogBg) {
    if (page === 'changelogs') {
      changelogBg.classList.remove('hidden');
    } else {
      changelogBg.classList.add('hidden');
    }
  }
  
  // Load page content if needed
  if (!pageCache[page]) {
    await loadPageContent(page);
  }
  
  // Show the selected page
  const pageElement = document.getElementById(`${page}-page`);
  if (pageElement) {
    pageElement.classList.add('active', 'fade-in');
    
    // Initialize page if needed
    if (pageInitializers[page]) {
      pageInitializers[page](params);
    }
    
    // Update document title
    updatePageTitle(page, params);
  }
}

// Load page content
async function loadPageContent(page) {
  const pageElement = document.getElementById(`${page}-page`);
  if (!pageElement) return;
  
  try {
    let htmlPath;
    
    switch (page) {
      case 'home':
        await loadHomePage(pageElement);
        break;
      case 'blog':
        await loadBlogPage(pageElement);
        break;
      case 'download':
        await loadDownloadPage(pageElement);
        break;
      case 'post':
        await loadPostPage(pageElement);
        break;
      case 'changelogs':
        await loadChangelogsPage(pageElement);
        break;
    }
    
    // Cache the page content
    pageCache[page] = true;
  } catch (error) {
    console.error(`Failed to load ${page} page:`, error);
    pageElement.innerHTML = `<div class="text-center py-20"><h2 class="text-white text-2xl">Error loading page</h2></div>`;
  }
}

// Update page title based on current page
function updatePageTitle(page, params = {}) {
  let title = 'Floaty';
  
  switch (page) {
    case 'home':
      title = 'Floaty';
      break;
    case 'blog':
      title = 'Blog - Floaty';
      break;
    case 'download':
      title = 'Download - Floaty';
      break;
    case 'post':
      // For posts, we'll update the title when the post data is loaded
      break;
    case 'changelogs':
      title = 'Changelogs - Floaty';
      break;
  }
  
  document.title = title;
}

// Load scripts dynamically
async function loadScript(url) {
  if (scriptCache[url]) {
    return scriptCache[url];
  }
  
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = url;
    script.onload = () => {
      scriptCache[url] = true;
      resolve();
    };
    script.onerror = (error) => reject(error);
    document.body.appendChild(script);
  });
}

// HOME PAGE
async function loadHomePage(pageElement) {
  try {
    const response = await fetch('/index.html');
    const html = await response.text();
    
    // Extract metadata from the HTML
    if (!metadataCache.home) {
      metadataCache.home = extractMetadata(html);
    }
    
    // Apply metadata
    applyMetadata(metadataCache.home);
    
    // Extract content from the home page
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    
    // Get everything between the navbar placeholder and footer container
    const content = extractContentBetween(
      tempDiv, 
      'navbar-placeholder', 
      'footer-container'
    );
    
    pageElement.innerHTML = content;
  } catch (error) {
    console.error('Error loading home page:', error);
    pageElement.innerHTML = `
    <div class="text-white text-center py-10">
      <h2 class="text-xl font-bold mb-2">Error loading home page</h2>
      <p class="text-gray-400">Please notify us on the Floaty Discord if this continues.</p>
    </div>`;
  }
}

function initHomePage() {
  // Initialize any scripts needed for the home page
  const script = document.createElement('script');
  script.textContent = `
    // Helper to scroll to Why floaty section
    function scrollToAbout() {
      const aboutSection = document.querySelector('h2.font-bold.text-white.text-center.mb-14');
      if (aboutSection) {
        aboutSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    }

    // Desktop navbar: About button
    function bindDesktopAbout() {
      // Wait for navbar to be injected
      const navCheck = setInterval(() => {
        const nav = document.getElementById('navbar-placeholder');
        if (!nav || !nav.querySelector) return;
        // Desktop About
        const aboutLink = nav.querySelector('.md\\\\:flex a:nth-child(2)');
        if (aboutLink && !aboutLink.dataset.scrollBound) {
          aboutLink.dataset.scrollBound = 'true';
          aboutLink.addEventListener('click', function (e) {
            e.preventDefault();
            history.replaceState(null, '', '#about');
            scrollToAbout();
          });
          clearInterval(navCheck);
        }
      }, 100);
    }

    // Mobile menu: About button
    function bindMobileAbout() {
      const navCheck = setInterval(() => {
        const nav = document.getElementById('navbar-placeholder');
        if (!nav || !nav.querySelector) return;
        // Mobile About
        const mobileAbout = nav.querySelector('#mobile-menu a:nth-child(3)');
        if (mobileAbout && !mobileAbout.dataset.scrollBound) {
          mobileAbout.dataset.scrollBound = 'true';
          mobileAbout.addEventListener('click', function (e) {
            e.preventDefault();
            // Hide mobile menu if open
            const menu = nav.querySelector('#mobile-menu');
            if (menu) {
              menu.classList.add('invisible', 'opacity-0', 'pointer-events-none');
            }
            history.replaceState(null, '', '#about');
            scrollToAbout();
          });
          clearInterval(navCheck);
        }
      }, 100);
    }

    // Attach smooth scroll to "Learn More" button in hero
    var learnMoreBtn = document.querySelector('.learn-more-btn');
    if (learnMoreBtn) {
      learnMoreBtn.addEventListener('click', function(e) {
        e.preventDefault();
        scrollToAbout();
      });
    }

    // Scroll on page load if #about is present
    if (window.location.hash === '#about') {
      setTimeout(scrollToAbout, 200); // Wait for DOM/render
    }

    bindDesktopAbout();
    bindMobileAbout();
    
    // Initialize blog cards
    import('./blog-card-utils.js').then(mod => {
      fetch('/api/posts')
        .then(res => res.json())
        .then(data => {
          const posts = data.posts || [];
          return fetch('/blog-card.html').then(res => res.text()).then(templateHTML => {
            const list = document.getElementById('home-blog-list');
            if (!list) return;
            
            posts.slice(0, 3).forEach(post => {
              const temp = document.createElement('div');
              temp.innerHTML = templateHTML;
              const card = temp.firstElementChild;
              card.querySelector('[data-type="badge"]').textContent = post.type.charAt(0).toUpperCase() + post.type.slice(1);
              card.querySelector('[data-type="badge"]').className += \` \${mod.badgeColors[post.type] || ''}\`;
              card.querySelector('[data-type="title"]').textContent = post.title;
              card.querySelector('[data-type="summary"]').textContent = post.summary;
              card.querySelector('[data-type="date"]').textContent = mod.formatDate(post.date || post.createdAt);
              card.querySelector('[data-type="thumbnail"]').src = post.thumbnail;
              card.href = post.type == 'changelog' ? \`/changelog#\${post.version}\` : \`/post/\${post.url}\`;
              // Render tags
              const tagsDiv = card.querySelector('[data-type="tags"]');
              tagsDiv.innerHTML = '';
              (post.tags || []).forEach(tag => {
                const tagEl = document.createElement('span');
                tagEl.className = 'px-2 py-0.5 rounded-full text-xs font-normal ml-1';
                tagEl.style.backgroundColor = tag.color || '#6366f1';
                tagEl.style.color = '#fff';
                tagEl.textContent = tag.name;
                tagsDiv.appendChild(tagEl);
              });
              list.appendChild(card);
            });
          });
        });
    });
  `;
  document.body.appendChild(script);
}

// BLOG PAGE
async function loadBlogPage(pageElement) {
  try {
    const response = await fetch('/blog.html');
    const html = await response.text();
    
    // Extract metadata from the HTML
    if (!metadataCache.blog) {
      metadataCache.blog = extractMetadata(html);
    }
    
    // Apply metadata
    applyMetadata(metadataCache.blog);
    
    // Extract content from the blog page
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    
    // Get everything between the navbar placeholder and footer container
    const content = extractContentBetween(
      tempDiv, 
      'navbar-placeholder', 
      'footer-container'
    );
    
    pageElement.innerHTML = content;
  } catch (error) {
    console.error('Error loading blog page:', error);
    pageElement.innerHTML = `
    <div class="text-white text-center py-10">
      <h2 class="text-xl font-bold mb-2">Error loading blog</h2>
      <p class="text-gray-400">Please notify us on the Floaty Discord if this continues.</p>
    </div>`;
  }
}

function initBlogPage() {
  // Initialize blog page functionality
  const script = document.createElement('script');
  script.type = 'module';
  script.textContent = `
    import('./blog-card-utils.js').then(mod => {
      fetch('/api/posts?type=blog')
        .then(res => res.json())
        .then(data => {
          const posts = data.posts || [];
          let filteredPosts = posts;
          const list = document.getElementById('blog-list');
          const searchInput = document.getElementById('blog-search');
          if (!list) return;
          Promise.all([
            fetch('/blog-card-alt.html').then(res => res.text()),
            fetch('/blog-card.html').then(res => res.text())
          ]).then(([altTemplate, cardTemplate]) => {
            function render(filtered) {
              list.innerHTML = '';
              // Featured
              filtered.slice(0, 2).forEach(post => {
                const temp = document.createElement('div');
                temp.innerHTML = altTemplate;
                const card = temp.firstElementChild;
                card.classList.add('md:col-span-2', 'w-full', 'px-3', 'md:px-0');
                card.querySelector('[data-type="title"]').textContent = post.title;
                card.querySelector('[data-type="summary"]').textContent = post.summary;
                card.querySelector('[data-type="date"]').textContent = mod.formatDate(post.date || post.createdAt);
                card.style.backgroundImage = \`url('\${post.thumbnail}')\`;
                card.querySelector('[data-type="href"]').href = post.type == 'changelog' ? \`/changelog#\${post.version}\` : \`/post/\${post.url}\`;
                // Render tags
                const tagsDiv = card.querySelector('[data-type="tags"]');
                tagsDiv.innerHTML = '';
                (post.tags || []).forEach(tag => {
                  const tagEl = document.createElement('span');
                  tagEl.className = 'px-2 py-0.5 rounded-full text-xs font-normal ml-1';
                  tagEl.style.backgroundColor = tag.color || '#6366f1';
                  tagEl.style.color = '#fff';
                  tagEl.textContent = tag.name;
                  tagsDiv.appendChild(tagEl);
                });
                list.appendChild(card);
              });
              // Regular
              filtered.slice(2).forEach(post => {
                const temp = document.createElement('div');
                temp.innerHTML = cardTemplate;
                const card = temp.firstElementChild;
                card.querySelector('[data-type="badge"]').style.display = 'none';
                card.querySelector('[data-type="title"]').textContent = post.title;
                card.querySelector('[data-type="summary"]').textContent = post.summary;
                card.querySelector('[data-type="date"]').textContent = mod.formatDate(post.date || post.createdAt);
                card.querySelector('[data-type="thumbnail"]').src = post.thumbnail;
                card.href = post.type == 'changelog' ? \`/changelog#\${post.version}\` : \`/post/\${post.url}\`;
                // Render tags
                const tagsDiv = card.querySelector('[data-type="tags"]');
                tagsDiv.innerHTML = '';
                (post.tags || []).forEach(tag => {
                  const tagEl = document.createElement('span');
                  tagEl.className = 'px-2 py-0.5 rounded-full text-xs font-normal ml-1';
                  tagEl.style.backgroundColor = tag.color || '#6366f1';
                  tagEl.style.color = '#fff';
                  tagEl.textContent = tag.name;
                  tagsDiv.appendChild(tagEl);
                });
                list.appendChild(card);
              });
            }
            // Initial render
            render(filteredPosts);
            // Search functionality
            searchInput.addEventListener('input', () => {
              const q = searchInput.value.trim().toLowerCase();
              let filtered = posts;
              if (q.startsWith('#')) {
                const tagQuery = q.slice(1);
                filtered = posts.filter(post => (post.tags || []).some(tag => tag.name.toLowerCase() === tagQuery));
              } else if (q.includes('#')) {
                // Allow "foo #tag" style
                const [main, ...tags] = q.split('#');
                const mainQuery = main.trim();
                const tagQuery = tags.join('#').trim();
                filtered = posts.filter(post => {
                  const matchesMain =
                    mainQuery.length === 0 ||
                    post.title.toLowerCase().includes(mainQuery) ||
                    post.summary.toLowerCase().includes(mainQuery);
                  const matchesTag =
                    tagQuery.length === 0 ||
                    (post.tags || []).some(tag => tag.name.toLowerCase() === tagQuery);
                  return matchesMain && matchesTag;
                });
              } else if (q.length > 0) {
                filtered = posts.filter(post =>
                  post.title.toLowerCase().includes(q) ||
                  post.summary.toLowerCase().includes(q)
                );
              }
              render(filtered);
            });
          });
        });
    });
  `;
  document.body.appendChild(script);
}

// DOWNLOAD PAGE
async function loadDownloadPage(pageElement) {
  try {
    const response = await fetch('/download.html');
    const html = await response.text();
    
    // Extract metadata from the HTML
    if (!metadataCache.download) {
      metadataCache.download = extractMetadata(html);
    }
    
    // Apply metadata
    applyMetadata(metadataCache.download);
    
    // Extract content from the download page
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    
    // Get everything between the navbar placeholder and footer container
    const content = extractContentBetween(
      tempDiv, 
      'navbar-placeholder', 
      'footer-container'
    );
    
    pageElement.innerHTML = content;
  } catch (error) {
    console.error('Error loading download page:', error);
    pageElement.innerHTML = `
    <div class="text-white text-center py-10">
      <h2 class="text-xl font-bold mb-2">Error loading download page</h2>
      <p class="text-gray-400">Please notify us on the Floaty Discord if this continues.</p>
    </div>`;
  }
}

function initDownloadPage() {
  // Load the download.js script first
  loadScript('/download.js').then(() => {
    // Manually initialize the download page functionality that would normally 
    // run when the script loads
    
    // These platform and channel variables are defined in download.js
    const platformBtnIds = ['platform-windows', 'platform-macos', 'platform-linux', 'platform-android', 'platform-ios'];
    const channelBtnIds3 = ['release-btn', 'beta-btn', 'nightly-btn'];
    
    // Set up platform button event listeners
    platformBtnIds.forEach(id => {
      const btn = document.getElementById(id);
      if (!btn) return;
      btn.addEventListener('click', function() {
        if (this.classList.contains('active') || this.disabled) return;
        
        // Update UI to show this platform is selected
        platformBtnIds.forEach(btnId => {
          const otherBtn = document.getElementById(btnId);
          if (otherBtn) {
            otherBtn.classList.remove('bg-[#64009E]', 'text-white', 'active');
            otherBtn.classList.add('text-white/80');
            otherBtn.setAttribute('aria-pressed', 'false');
          }
        });
        
        this.classList.remove('text-white/80');
        this.classList.add('bg-[#64009E]', 'text-white', 'active');
        this.setAttribute('aria-pressed', 'true');
        
        // Update download options based on platform
        if (typeof updateDownloadOptions === 'function') {
          updateDownloadOptions();
        }
      });
    });
    
    // Set up channel button event listeners
    channelBtnIds3.forEach(id => {
      const btn = document.getElementById(id);
      if (!btn) return;
      btn.addEventListener('click', function() {
        if (this.classList.contains('active') || this.disabled) return;
        
        // Update UI to show this channel is selected
        channelBtnIds3.forEach(btnId => {
          const otherBtn = document.getElementById(btnId);
          if (otherBtn) {
            otherBtn.classList.remove('bg-[#64009E]', 'text-white', 'active');
            otherBtn.classList.add('text-white/80');
            otherBtn.setAttribute('aria-pressed', 'false');
          }
        });
        
        this.classList.remove('text-white/80');
        this.classList.add('bg-[#64009E]', 'text-white', 'active');
        this.setAttribute('aria-pressed', 'true');
        
        // Update download options based on channel
        if (typeof updateDownloadOptions === 'function') {
          updateDownloadOptions();
        }
      });
    });
    
    // Initial call to update download options
    if (typeof updateDownloadOptions === 'function') {
      updateDownloadOptions();
    }
  });
}

// POST PAGE
async function loadPostPage(pageElement) {
  try {
    const response = await fetch('/post.html');
    const html = await response.text();
    
    // Extract template metadata from the HTML
    if (!metadataCache.post) {
      metadataCache.post = extractMetadata(html);
    }
    
    // Note: For post pages, we'll apply dynamic metadata in the initPostPage function
    // based on the specific post content after fetching it
    
    // Extract content from the post page
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    
    // Get everything between the navbar placeholder and footer container
    const content = extractContentBetween(
      tempDiv, 
      'navbar-placeholder', 
      'footer-container'
    );
    
    pageElement.innerHTML = content;
  } catch (error) {
    console.error('Error loading post page:', error);
    pageElement.innerHTML = `
    <div class="text-white text-center py-10">
      <h2 class="text-xl font-bold mb-2">Error loading post</h2>
      <p class="text-gray-400">Please notify us on the Floaty Discord if this continues.</p>
    </div>`;
  }
}

function initPostPage(params) {
  // Create a function to escape single quotes in strings
  const escapeSingleQuotes = (str) => {
    return str ? str.replace(/'/g, '\\' + "'" ) : '';
  };

  // Create the script content as a string with proper escaping
  const scriptContent = [
    '// Utility: get slug from URL (expected pattern: /post/<slug>)',
    'function getSlugFromPath() {',
    '  const match = window.location.pathname.match(\'/post/([^/]+)\');',
    '  return match ? decodeURIComponent(match[1]) : null;',
    '}',
    '',
    '// Apply dynamic metadata for a specific post',
    'function applyPostMetadata(post) {',
    '  // Clear any existing dynamic metadata',
    '  document.querySelectorAll(\'meta[data-spa-meta="true"], link[data-spa-meta="true"]\').forEach(el => el.remove());',
    '  ',
    '  // Set document title',
    '  document.title = post ? (post.title + \' - Floaty\') : \'Not Found - Floaty\';',
    '  ',
    '  if (!post) return;',
    '  ',
    '  // Create meta tags for the post',
    '  const metaTags = [',
    '    // Basic metadata',
    '    { name: \'description\', content: post.summary || \'\' },',
    '    // Open Graph metadata',
    '    { property: \'og:type\', content: \'article\' },',
    '    { property: \'og:title\', content: post.title + \' - Floaty\' || \'\' },',
    '    { property: \'og:description\', content: post.summary || \'\' },',
    '    { property: \'og:url\', content: window.location.origin + \'/post/\' + (post.url || getSlugFromPath() || \'\') },',
    '    { property: \'og:image\', content: post.thumbnail || \'\' },,',
    '    // Twitter Card metadata',
    '    { name: \'twitter:card\', content: \'summary_large_image\' },',
    '    { name: \'twitter:title\', content: post.title + \' - Floaty\' || \'\' },',
    '    { name: \'twitter:description\', content: post.summary || \'\' },',
    '    { name: \'twitter:image\', content: post.thumbnail || \'\' }',
    '  ];',
    '  ',
    '  // Add article metadata if available',
    '  if (post.date || post.createdAt) {',
    '    metaTags.push({ property: \'article:published_time\', content: post.date || post.createdAt });',
    '  }',
    '  if (post.author) {',
    '    metaTags.push({ property: \'article:author\', content: post.author });',
    '  }',
    '  ',
    '  // Add tags as keywords',
    '  if (Array.isArray(post.tags) && post.tags.length > 0) {',
    '    const keywords = post.tags.map(tag => typeof tag === \'object\' ? tag.name : tag).join(\', \');',
    '    if (keywords) {',
    '      metaTags.push({ name: \'keywords\', content: keywords });',
    '    }',
    '  }',
    '  ',
    '  // Create and append meta elements',
    '  metaTags.forEach(meta => {',
    '    const metaElement = document.createElement(\'meta\');',
    '    Object.keys(meta).forEach(key => {',
    '      metaElement.setAttribute(key, meta[key]);',
    '    });',
    '    metaElement.setAttribute(\'data-spa-meta\', \'true\');',
    '    document.head.appendChild(metaElement);',
    '  });',
    '  ',
    '  // Create canonical link',
    '  const canonicalLink = document.createElement(\'link\');',
    '  canonicalLink.setAttribute(\'rel\', \'canonical\');',
    '  canonicalLink.setAttribute(\'href\', window.location.origin + \'/post/\' + (post.url || getSlugFromPath() || \'\'));',
    '  canonicalLink.setAttribute(\'data-spa-meta\', \'true\');',
    '  document.head.appendChild(canonicalLink);',
    '}',
    '',
    'async function fetchAndRenderPost() {',
    '  const slug = getSlugFromPath();',
    '  if (!slug) {',
    '    document.getElementById(\'post-title\').textContent = \'Post Not Found\';',
    '    document.getElementById(\'post-summary\').textContent = \'\';',
    '    document.getElementById(\'post-content\').textContent = \'\';',
    '    // Apply metadata for not found page',
    '    applyPostMetadata(null);',
    '    return;',
    '  }',
    '  try {',
    '    const res = await fetch(\'/api/post/\' + encodeURIComponent(slug));',
    '    if (!res.ok) throw new Error(\'Post not found\');',
    '    const post = await res.json();',
    '    ',
    '    // Apply dynamic metadata based on post content',
    '    applyPostMetadata(post);',
    '    ',
    '    // Title & summary',
    '    if (document.getElementById(\'post-title\')) {',
    '      document.getElementById(\'post-title\').textContent = post.title || \'\';',
    '    }',
    '    if (document.getElementById(\'post-summary\')) {',
    '      document.getElementById(\'post-summary\').textContent = post.summary || \'\';',
    '    }',
    '    ',
    '    // Content (markdown-it to HTML)',
    '    const contentElement = document.getElementById(\'post-content\');',
    '    if (contentElement) {',
    '      if (window.markdownit) {',
    '        const md = window.markdownit();',
    '        contentElement.innerHTML = md.render(post.content || \'\');',
    '      } else {',
    '        contentElement.textContent = post.content || \'\';',
    '      }',
    '    }',
    '    ',
    '    // Date & author',
    '    if (document.getElementById(\'post-date\')) {',
    '      document.getElementById(\'post-date\').textContent = post.date || post.createdAt || \'\';',
    '    }',
    '    if (document.getElementById(\'post-author\')) {',
    '      document.getElementById(\'post-author\').textContent = post.author || \'\';',
    '    }',
    '    ',
    '    // Tags',
    '    const tagsDiv = document.getElementById(\'post-tags\');',
    '    if (tagsDiv) {',
    '      tagsDiv.innerHTML = \'\';',
    '      if (Array.isArray(post.tags)) {',
    '        post.tags.forEach(tag => {',
    '          const span = document.createElement(\'span\');',
    '          span.className = \'px-2 py-0.5 rounded-full text-xs font-semibold text-white\';',
    '          span.style.backgroundColor = tag.color || \'#6366f1\';',
    '          span.textContent = tag.name || tag;',
    '          tagsDiv.appendChild(span);',
    '        });',
    '      }',
    '    }',
    '    ',
    '    // Images',
    '    if (post.thumbnail) {',
    '      if (document.getElementById(\'post-main-img\')) {',
    '        document.getElementById(\'post-main-img\').src = post.thumbnail;',
    '      }',
    '      const bgImgEl = document.getElementById(\'post-bg-img-inner\');',
    '      if (bgImgEl) {',
    '        try {',
    '          // Use JSON.stringify to properly escape the URL',
    '          const safeUrl = JSON.stringify(post.thumbnail).slice(1, -1);',
    '          bgImgEl.style.backgroundImage = \'url(\' + safeUrl + \')\';',
    '        } catch (e) {',
    '          console.error(\'Error setting background image:\', e);',
    '        }',
    '      }',
    '    }',
    '  } catch (e) {',
    '    console.error(\'Error loading post:\', e);',
    '    if (document.getElementById(\'post-title\')) {',
    '      document.getElementById(\'post-title\').textContent = \'Post Not Found\';',
    '    }',
    '    if (document.getElementById(\'post-summary\')) {',
    '      document.getElementById(\'post-summary\').textContent = \'\';',
    '    }',
    '    if (document.getElementById(\'post-content\')) {',
    '      document.getElementById(\'post-content\').textContent = \'\';',
    '    }',
    '    // Apply metadata for not found page',
    '    applyPostMetadata(null);',
    '  }',
    '}',
    '',
    '// Initialize the post',
    'fetchAndRenderPost();'
  ].join('\n');

  // Create and append the script
  const script = document.createElement('script');
  script.textContent = scriptContent;
  document.body.appendChild(script);
}

// ...
// CHANGELOGS PAGE
async function loadChangelogsPage(pageElement) {
  try {
    // Load the changelogs HTML content
    const response = await fetch('/changelogs.html');
    const html = await response.text();
    
    // Extract metadata from the HTML
    if (!metadataCache.changelogs) {
      metadataCache.changelogs = extractMetadata(html);
    }
    
    // Apply metadata
    applyMetadata(metadataCache.changelogs);
    
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, 'text/html');
    
    // Get the main content
    const mainContent = doc.querySelector('main').outerHTML;
    
    // Set the main content
    pageElement.innerHTML = mainContent;
    
    // Load and initialize the changelogs module
    try {
      // Load the script
      await loadScript('/changelogs.js');
      // Wait a small amount of time for the script to register
      await new Promise(resolve => setTimeout(resolve, 100));
      
      // Initialize the changelogs
      if (window.changelogsModule && window.changelogsModule.initializeChangelogs) {
        window.changelogsModule.initializeChangelogs();
      } else {
        console.error('Changelogs module not properly loaded');
      }

    } catch (scriptError) {
      console.error('Error loading changelogs script:', scriptError);
      throw new Error('Failed to load changelogs functionality');
    }
  } catch (error) {
    console.error('Error loading changelogs page:', error);
    pageElement.innerHTML = `
      <div class="text-white text-center py-10">
        <h2 class="text-xl font-bold mb-2">Error loading changelogs</h2>
        <p class="text-gray-400">Please notify us on the Floaty Discord if this continues.</p>
      </div>`;
  }
}

function initChangelogsPage() {
  // Instead of just loading the script, we need to execute the initialization code
  // that would normally run on DOMContentLoaded
  
  // Setup channel selector buttons
  const channelBtnIds3 = ['changelog-btn-all', 'changelog-btn-release', 'changelog-btn-beta', 'changelog-btn-nightly'];
  const channelKeyMap3 = {
    'changelog-btn-all': 'all',
    'changelog-btn-release': 'release',
    'changelog-btn-beta': 'beta',
    'changelog-btn-nightly': 'nightly',
  };
  let currentChannel3 = 'all';
  
  // Load the changelogs.js script first to get all the functions
  loadScript('/changelogs.js').then(() => {
    // Now manually run the initialization code that would normally be in the DOMContentLoaded event
    channelBtnIds3.forEach(id => {
      const btn = document.getElementById(id);
      if (!btn) return;
      btn.addEventListener('click', () => {
        if (btn.disabled) return;
        const prevChannel = currentChannel3;
        currentChannel3 = channelKeyMap3[id];
        
        // Call the function from changelogs.js
        if (typeof fetchAndRenderChangelogsByChannel === 'function') {
          fetchAndRenderChangelogsByChannel({ revertOnFail: true, prevChannel });
        }
      });
    });
    
    const list = document.getElementById('changelog-list');
    fetch('/api/posts?type=changelog')
      .then(res => res.json())
      .then(data => {
        window.allChangelogs = data.posts || [];
        window.changelogsModule.scrollToChangelog();

        
        // Call functions from changelogs.js
        if (typeof fetchAndRenderChangelogsByChannel === 'function') {
          fetchAndRenderChangelogsByChannel({ revertOnFail: false });
        }
        
        if (typeof updateActiveButton === 'function') {
          updateActiveButton(channelBtnIds3, channelBtnIds3.find(id => channelKeyMap3[id] === currentChannel3));
        }
        
        if (!list) return;

        
        
        // Use renderChangelogCard from changelogs.js if available
        if (typeof renderChangelogCard === 'function') {
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
        }
      });
  });
}

// Utility function to extract content between two elements
function extractContentBetween(container, startId, endId) {
  const elements = container.children;
  let content = '';
  let capturing = false;
  
  for (let i = 0; i < elements.length; i++) {
    const element = elements[i];
    
    if (element.id === startId) {
      capturing = true;
      continue;
    }
    
    if (element.id === endId) {
      break;
    }
    
    if (capturing) {
      content += element.outerHTML;
    }
  }
  
  return content;
}

// Extract metadata from HTML
function extractMetadata(html) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, 'text/html');
  const metaTags = doc.querySelectorAll('meta');
  const linkTags = doc.querySelectorAll('link[rel="canonical"], link[rel="alternate"]');
  const titleTag = doc.querySelector('title');
  
  const metadata = {
    meta: Array.from(metaTags).map(tag => tag.outerHTML),
    links: Array.from(linkTags).map(tag => tag.outerHTML),
    title: titleTag ? titleTag.textContent : null
  };
  
  return metadata;
}

// Apply metadata to document head
function applyMetadata(metadata) {
  if (!metadata) return;
  
  // Set title if provided
  if (metadata.title) {
    document.title = metadata.title;
  }
  
  // Add meta tags
  if (metadata.meta && metadata.meta.length > 0) {
    const metaContainer = document.createElement('div');
    metadata.meta.forEach(metaHTML => {
      metaContainer.innerHTML = metaHTML;
      const meta = metaContainer.firstChild;
      // Mark as SPA metadata for easy removal later
      meta.setAttribute('data-spa-meta', 'true');
      document.head.appendChild(meta);
    });
  }
  
  // Add link tags
  if (metadata.links && metadata.links.length > 0) {
    const linkContainer = document.createElement('div');
    metadata.links.forEach(linkHTML => {
      linkContainer.innerHTML = linkHTML;
      const link = linkContainer.firstChild;
      // Mark as SPA metadata for easy removal later
      link.setAttribute('data-spa-meta', 'true');
      document.head.appendChild(link);
    });
  }
}

// Clear existing dynamic metadata
function clearMetadata() {
  // Remove meta tags added by the router
  document.querySelectorAll('meta[data-spa-meta="true"]').forEach(tag => tag.remove());
  
  // Remove link tags added by the router
  document.querySelectorAll('link[data-spa-meta="true"]').forEach(tag => tag.remove());
}
