document.addEventListener('DOMContentLoaded', () => {
  const typingTextEl = document.getElementById('demo-typing-text');
  const visualizerEl = document.querySelector('.visualizer-container');
  const windowTitlePill = document.querySelector('.window-title-pill');
  
  const scenarios = [
    {
      app: 'Terminal',
      pillText: 'active_app: terminal',
      spoken: 'git commit this is a good landing page',
      transformed: '<span class="typed-command">git commit -m "this is a good landing page"</span>',
      isHTML: true,
      holdTime: 2000,
      readTime: 4000
    },
    {
      app: 'Slack',
      pillText: 'active_app: slack',
      spoken: 'hey team just wanted to follow up on the design review the new direction looks great let\'s',
      transformed: '"hey team, just wanted to follow up on the design review. the new direction looks great—let\'s |"',
      isHTML: false,
      holdTime: 3200,
      readTime: 4000
    },
    {
      app: 'Gmail',
      pillText: 'active_app: gmail',
      spoken: 'email John about the launch tomorrow tell him we are ready',
      transformed: 'Hi John,\n\nI wanted to follow up about the launch tomorrow. Just letting you know we are ready.\n\nBest regards,\n[Your Name]',
      isHTML: false,
      holdTime: 2800,
      readTime: 5000
    }
  ];
  
  let currentScenarioIndex = 0;
  
  async function runTypewriter() {
    const scenario = scenarios[currentScenarioIndex];
    
    // Update active app pill title
    if (windowTitlePill) {
      windowTitlePill.innerHTML = `<span class="pill-text">${scenario.pillText}</span>`;
    }
    
    // 1. Start Dictation (waveform animates)
    if (visualizerEl) {
      visualizerEl.classList.add('recording');
    }
    if (typingTextEl) {
      typingTextEl.innerHTML = '"';
    }
    
    // Type the spoken text letter by letter
    const spokenText = scenario.spoken;
    for (let i = 0; i < spokenText.length; i++) {
      if (typingTextEl) {
        typingTextEl.innerHTML = '"' + spokenText.substring(0, i + 1) + '|"';
      }
      // Vary typing speed slightly for realism
      await delay(35 + Math.random() * 45);
    }
    
    // Remove the cursor bar at the end of spoken
    if (typingTextEl) {
      typingTextEl.innerHTML = '"' + spokenText + '"';
    }
    
    // 2. Stop Dictation (waveform stops)
    await delay(500);
    if (visualizerEl) {
      visualizerEl.classList.remove('recording');
    }
    
    // Subtle loading pause
    if (typingTextEl) {
      typingTextEl.innerHTML = '"' + spokenText + '" <span class="processing-dot">...</span>';
    }
    await delay(800);
    
    // 3. Apply App-Aware AI Post-processing conversion
    if (typingTextEl) {
      if (scenario.isHTML) {
        typingTextEl.innerHTML = scenario.transformed;
      } else {
        // Simple pre-tag styling for linebreaks in emails
        if (scenario.app === 'Gmail') {
          typingTextEl.style.fontSize = '15px';
          typingTextEl.style.textAlign = 'left';
          typingTextEl.style.fontFamily = 'var(--font-sans)';
          typingTextEl.innerHTML = scenario.transformed.replace(/\n/g, '<br>');
        } else {
          typingTextEl.style.fontSize = '20px';
          typingTextEl.style.textAlign = 'center';
          typingTextEl.innerHTML = scenario.transformed;
        }
      }
    }
    
    // Read time for user
    await delay(scenario.readTime);
    
    // Reset styles for next scenario
    if (typingTextEl) {
      typingTextEl.style.fontSize = '';
      typingTextEl.style.textAlign = '';
      typingTextEl.style.fontFamily = '';
    }
    
    // Move to next scenario
    currentScenarioIndex = (currentScenarioIndex + 1) % scenarios.length;
    runTypewriter();
  }
  
  function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
  
  // Start the infinite loop
  runTypewriter();
  
  // Smooth scroll for nav links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({
          behavior: 'smooth'
        });
      }
    });
  });

  // Watch Demo button scrolls to demo section
  const watchBtn = document.getElementById('watch-btn');
  if (watchBtn) {
    watchBtn.addEventListener('click', () => {
      const demoSection = document.getElementById('demo');
      if (demoSection) {
        demoSection.scrollIntoView({
          behavior: 'smooth'
        });
      }
    });
  }

  // Mobile menu morphing toggle logic
  const menuToggle = document.getElementById('menu-toggle');
  const navbar = document.querySelector('.navbar');
  if (menuToggle && navbar) {
    menuToggle.addEventListener('click', () => {
      navbar.classList.toggle('expanded');
    });

    // Close menu when clicking nav links
    document.querySelectorAll('.nav-link').forEach(link => {
      link.addEventListener('click', () => {
        navbar.classList.remove('expanded');
      });
    });
  }

  // Scroll reveal animation with IntersectionObserver
  const observerOptions = {
    root: null,
    rootMargin: '0px',
    threshold: 0.1
  };

  const revealObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('active');
        // Once visible, stop tracking
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  document.querySelectorAll('.scroll-reveal').forEach(el => {
    revealObserver.observe(el);
  });
});
