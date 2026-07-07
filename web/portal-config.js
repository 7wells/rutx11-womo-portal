// Central portal link configuration.
//
// Edit these URLs when your local camper network uses different addresses.
// The portal itself does not need a fixed URL here; it uses the address from
// which the browser opened it, for example a LAN address or a VPN address.
window.WOMO_PORTAL_CONFIG = Object.freeze({
  // Teltonika router web UI. RUTX11 installations often use HTTPS here.
  routerGuiUrl: 'https://192.168.11.1/',

  // ESP32 Main web UI and event source base URL.
  esp32MainUrl: 'http://192.168.11.3/',

  // Local Truma/Smartavan web UI.
  trumaUrl: 'http://192.168.11.4/'
});
