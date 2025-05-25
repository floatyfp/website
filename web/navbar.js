// Hamburger menu toggle for modular navbar
(function() {
  // Hamburger menu toggle for modular navbar
  const navToggle = document.getElementById('nav-toggle');
  const navClose = document.getElementById('nav-close');
  const mobileMenu = document.getElementById('mobile-menu');
  const body = document.body;

  function openMenu() {
    mobileMenu.classList.remove('invisible', 'opacity-0', 'pointer-events-none');
    mobileMenu.classList.add('visible', 'opacity-100', 'pointer-events-auto');
    body.classList.add('overflow-hidden');
  }
  function closeMenu() {
    mobileMenu.classList.remove('visible', 'opacity-100', 'pointer-events-auto');
    mobileMenu.classList.add('invisible', 'opacity-0', 'pointer-events-none');
    body.classList.remove('overflow-hidden');
  }
  if (navToggle && mobileMenu) {
    navToggle.addEventListener('click', () => {
      if (mobileMenu.classList.contains('visible')) {
        closeMenu();
      } else {
        openMenu();
      }
    });
  }
  if (navClose) {
    navClose.addEventListener('click', closeMenu);
  }
})();

