// main.js

document.addEventListener('DOMContentLoaded', () => {
    // Smooth scrolling for navigation links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const targetId = this.getAttribute('href');
            if(targetId === '#') return;
            
            const targetElement = document.querySelector(targetId);
            if(targetElement) {
                targetElement.scrollIntoView({
                    behavior: 'smooth'
                });
            }
        });
    });

    // Populate images if they exist in the public/images folder
    // When the user provides screenshots, we just drop them in public/images/ and name them correctly.
    const images = {
        'img-floorplan': 'images/floorplan.webp',
        'img-pdn': 'images/pdn.webp',
        'img-placement': 'images/placement.webp',
        'img-routing': 'images/routing.webp'
    };

    // To test if images load and display them
    Object.keys(images).forEach(id => {
        const imgElement = document.getElementById(id);
        if (imgElement) {
            // Attempt to load. The vite dev server will serve from public/
            const img = new Image();
            img.onload = () => { imgElement.src = images[id]; imgElement.parentElement.classList.remove('skeleton'); };
            img.onerror = () => { console.log(`Waiting for image: ${images[id]}`); };
            img.src = images[id];
        }
    });

    // Intersection Observer for scroll animations
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Apply fade-in to all items
    document.querySelectorAll('.glass-card, .timeline-item').forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.6s ease-out, transform 0.6s ease-out';
        observer.observe(el);
    });
});
