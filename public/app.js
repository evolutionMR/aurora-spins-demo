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

  // Demo-only bonus play-through. Each click moves it forward by 25%.
  var playthrough = 0;
  var ptButton = document.getElementById('playthrough-btn');
  var ptText = document.getElementById('playthrough-text');
  var ptFill = document.getElementById('playthrough-fill');
  var ptBar = ptFill.parentElement;

  ptButton.addEventListener('click', function () {
    playthrough = Math.min(100, playthrough + 25);
    ptText.textContent = playthrough + '%';
    ptFill.style.width = playthrough + '%';
    ptBar.setAttribute('aria-valuenow', String(playthrough));
    if (playthrough === 100) {
      ptButton.disabled = true;
    }
  });
})();
