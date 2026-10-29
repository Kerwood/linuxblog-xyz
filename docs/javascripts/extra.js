// Instant navigation swaps the logo on every page change but not the site
// name link added in overrides/partials/header.html, which would keep the
// previous page's relative href (on a post, a link to itself). Copy the
// logo's href over after each page load.
document$.subscribe(() => {
  const logo = document.querySelector(".md-header .md-logo")
  const name = document.querySelector(".md-header .lb-site-name")
  if (logo && name) name.href = logo.href
})
