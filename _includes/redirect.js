(function() {
  const redirects = {};
  {% for redirect in site.data.redirects %}
  redirects["{{ redirect.from }}"] = "{{ redirect.to }}";
  {% endfor %}
  const path = window.location.pathname;
  const redir = redirects[path];
  if (redir) {
    document.querySelector('#text-404').innerHTML = `Redirecting you to <a href="${redir}">${redir}<a/>`;
    window.location.href = redir;
  } else {
    document.querySelector('.page-title').innerText = "Not found"
    document.querySelector('#content-404').classList.remove('hidden')
  }
})();