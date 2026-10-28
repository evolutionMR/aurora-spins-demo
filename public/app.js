// Demo-only mission progress. No real deposits happen.
(function () {
  var deposits = 0;
  var button = document.getElementById('deposit');
  var text = document.getElementById('progress-text');
  var fill = document.getElementById('progress-fill');
  var bar = fill.parentElement;
  var reward = document.getElementById('reward');
  var spins = document.getElementById('spins');

  button.addEventListener('click', function () {
    deposits = Math.min(3, deposits + 1);
    text.textContent = deposits + ' of 3';
    fill.style.width = Math.round((deposits / 3) * 100) + '%';
    bar.setAttribute('aria-valuenow', String(deposits));
    if (deposits === 3) {
      button.disabled = true;
      reward.hidden = false;
      spins.textContent = '10';
    }
  });
})();
