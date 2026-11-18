// Shows the offer only for visitors from NJ or PA (from ?state=). Demo only.
(function () {
  var states = { NJ: 'New Jersey', PA: 'Pennsylvania' };
  var code = (new URLSearchParams(window.location.search).get('state') || '').trim().toUpperCase();
  var name = Object.prototype.hasOwnProperty.call(states, code) ? states[code] : null;

  if (name) {
    document.getElementById('tipoff-state').textContent = 'Offer for players in ' + name;
    document.getElementById('tipoff-offer').hidden = false;
  }

  document.getElementById('claim').addEventListener('click', function () {
    document.getElementById('claim-note').hidden = false;
  });
})();
