/* Lookout website: live radar map and the Drive mode voice sample. */
(function () {
  "use strict";

  /* ---------- Drive mode: hear a sample alert ---------- */
  var hear = document.getElementById("hear-alert");
  var hearNote = document.getElementById("hear-note");
  if (hear && "speechSynthesis" in window && "SpeechSynthesisUtterance" in window) {
    var label = hear.querySelector("span");
    var setPlaying = function (on) {
      hear.setAttribute("aria-pressed", on ? "true" : "false");
      label.textContent = on ? "Stop" : "Hear a sample alert";
    };
    hear.hidden = false;
    if (hearNote) hearNote.hidden = false;
    hear.addEventListener("click", function () {
      if (window.speechSynthesis.speaking) { window.speechSynthesis.cancel(); setPlaying(false); return; }
      // The exact words Drive mode says when a new warning arrives.
      var u = new SpeechSynthesisUtterance("Lookout. New alert: Severe Thunderstorm Warning.");
      u.lang = "en-US";
      u.onend = u.onerror = function () { setPlaying(false); };
      setPlaying(true);
      window.speechSynthesis.speak(u);
    });
  }

  /* ---------- Live radar ---------- */
  var mapEl = document.getElementById("radar-map");
  if (!mapEl) return;

  var timeEl = document.getElementById("radar-time");
  var countEl = document.getElementById("alert-count");
  var nSevere = document.getElementById("n-severe");
  var nOther = document.getElementById("n-other");
  var nQuakes = document.getElementById("n-quakes");
  var meBtn = document.getElementById("radar-me");
  var allBtn = document.getElementById("radar-all");
  var locNote = document.getElementById("loc-note");
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var CONUS = [[24.5, -124.8], [49.4, -66.9]];
  var IEM_META = "https://mesonet.agron.iastate.edu/data/gis/images/4326/USCOMP/n0q_0.json";
  var IEM_TILES = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/";
  var BOUNDARIES = "https://cdn.jsdelivr.net/npm/us-atlas@3.0.1/states-10m.json";
  // Storm-based alerts. These are the ones the Weather Service issues with a drawn polygon.
  var EVENTS = [
    "Tornado Warning", "Severe Thunderstorm Warning", "Flash Flood Warning", "Extreme Wind Warning",
    "Snow Squall Warning", "Dust Storm Warning", "Special Marine Warning", "Special Weather Statement",
    "Flood Advisory", "Flood Warning"
  ];

  // [name, lat, lon, tier] - tier 1 shows from far out, tier 3 only up close.
  var CITIES = [
    ["Seattle", 47.61, -122.33, 1], ["Los Angeles", 34.05, -118.24, 1], ["Denver", 39.74, -104.99, 1],
    ["Dallas", 32.78, -96.8, 1], ["Chicago", 41.88, -87.63, 1], ["Atlanta", 33.75, -84.39, 1],
    ["Miami", 25.76, -80.19, 1], ["New York", 40.71, -74.01, 1],
    ["San Francisco", 37.77, -122.42, 2], ["Phoenix", 33.45, -112.07, 2], ["Salt Lake City", 40.76, -111.89, 2],
    ["Houston", 29.76, -95.37, 2], ["Oklahoma City", 35.47, -97.52, 2], ["Kansas City", 39.1, -94.58, 2],
    ["Minneapolis", 44.98, -93.27, 2], ["New Orleans", 29.95, -90.07, 2], ["Nashville", 36.16, -86.78, 2],
    ["Detroit", 42.33, -83.05, 2], ["Washington", 38.91, -77.04, 2], ["Boston", 42.36, -71.06, 2],
    ["Portland", 45.52, -122.68, 3], ["Sacramento", 38.58, -121.49, 3], ["Las Vegas", 36.17, -115.14, 3],
    ["San Diego", 32.72, -117.16, 3], ["Albuquerque", 35.08, -106.65, 3], ["El Paso", 31.76, -106.49, 3],
    ["Boise", 43.62, -116.2, 3], ["Billings", 45.78, -108.5, 3], ["Omaha", 41.26, -95.94, 3],
    ["St. Louis", 38.63, -90.2, 3], ["Memphis", 35.15, -90.05, 3], ["Birmingham", 33.52, -86.8, 3],
    ["Jacksonville", 30.33, -81.66, 3], ["Tampa", 27.95, -82.46, 3], ["Orlando", 28.54, -81.38, 3],
    ["Charlotte", 35.23, -80.84, 3], ["Raleigh", 35.78, -78.64, 3], ["Richmond", 37.54, -77.44, 3],
    ["Philadelphia", 39.95, -75.17, 3], ["Pittsburgh", 40.44, -80.0, 3], ["Cleveland", 41.5, -81.69, 3],
    ["Columbus", 39.96, -83.0, 3], ["Indianapolis", 39.77, -86.16, 3], ["Louisville", 38.25, -85.76, 3],
    ["Milwaukee", 43.04, -87.91, 3], ["Des Moines", 41.59, -93.62, 3], ["Wichita", 37.69, -97.34, 3],
    ["Tulsa", 36.15, -95.99, 3], ["Little Rock", 34.75, -92.29, 3], ["Jackson", 32.3, -90.18, 3],
    ["Montgomery", 32.38, -86.3, 3], ["Savannah", 32.08, -81.09, 3], ["Macon", 32.84, -83.63, 3],
    ["Augusta", 33.47, -81.97, 3], ["Columbia", 34.0, -81.03, 3], ["Charleston", 32.78, -79.93, 3],
    ["Knoxville", 35.96, -83.92, 3], ["San Antonio", 29.42, -98.49, 3], ["Austin", 30.27, -97.74, 3],
    ["Amarillo", 35.22, -101.83, 3], ["Fargo", 46.88, -96.79, 3], ["Sioux Falls", 43.55, -96.73, 3],
    ["Buffalo", 42.89, -78.88, 3], ["Albany", 42.65, -73.76, 3], ["Tallahassee", 30.44, -84.28, 3],
    ["Mobile", 30.69, -88.04, 3], ["Shreveport", 32.53, -93.75, 3], ["Spokane", 47.66, -117.43, 3],
    ["Reno", 39.53, -119.81, 3], ["Tucson", 32.22, -110.97, 3], ["Cheyenne", 41.14, -104.82, 3],
    ["Rapid City", 44.08, -103.23, 3], ["Bismarck", 46.81, -100.78, 3], ["Helena", 46.59, -112.04, 3]
  ];

  var started = false;

  function fallback(msg) {
    mapEl.innerHTML = "";
    var p = document.createElement("p");
    p.className = "fallback";
    p.textContent = msg;
    mapEl.appendChild(p);
    if (timeEl) timeEl.textContent = "";
    if (meBtn) meBtn.disabled = true;
    if (allBtn) allBtn.disabled = true;
  }

  function start() {
    if (started) return;
    started = true;
    var L = window.L;
    if (!L) { fallback("The live map couldn't load. Check your connection and refresh the page."); return; }

    var map = L.map(mapEl, {
      zoomControl: false,
      minZoom: 3,
      maxZoom: 9,
      zoomSnap: 0.25,
      scrollWheelZoom: false,
      dragging: !L.Browser.mobile,
      maxBounds: [[8, -175], [72, -45]],
      maxBoundsViscosity: 0.7
    });
    L.control.zoom({ position: "topright" }).addTo(map);
    map.attributionControl.setPrefix(false);
    map.attributionControl.addAttribution(
      'Radar: NOAA NEXRAD via <a href="https://mesonet.agron.iastate.edu/">Iowa Environmental Mesonet</a>. ' +
      'Alerts: <a href="https://www.weather.gov/">National Weather Service</a>. Quakes: <a href="https://earthquake.usgs.gov/">USGS</a>. Borders: U.S. Census Bureau.'
    );

    map.createPane("land").style.zIndex = 200;
    map.createPane("radar").style.zIndex = 300;
    map.createPane("lines").style.zIndex = 350;
    map.createPane("alerts").style.zIndex = 420;
    map.createPane("labels").style.zIndex = 450;
    map.getPane("land").style.pointerEvents = "none";
    map.getPane("radar").style.pointerEvents = "none";
    map.getPane("lines").style.pointerEvents = "none";
    map.getPane("labels").style.pointerEvents = "none";

    var fit = function (animate) { map.fitBounds(CONUS, { padding: [10, 10], animate: animate && !reduceMotion }); };
    fit(false);

    var zoomClass = function () {
      var z = map.getZoom();
      mapEl.classList.toggle("z-far", z < 4);
      mapEl.classList.toggle("z-mid", z >= 4 && z < 5.75);
    };
    map.on("zoomend", zoomClass);
    zoomClass();

    // State outlines (U.S. Census cartographic boundaries, via us-atlas).
    if (window.topojson) {
      fetch(BOUNDARIES).then(function (r) { return r.json(); }).then(function (us) {
        L.geoJSON(window.topojson.feature(us, us.objects.nation), {
          pane: "land", interactive: false,
          style: { color: "#3b4c63", weight: 1, fillColor: "#141c27", fillOpacity: 1 }
        }).addTo(map);
        L.geoJSON(window.topojson.mesh(us, us.objects.states, function (a, b) { return a !== b; }), {
          pane: "lines", interactive: false,
          style: { color: "#40536b", weight: 0.8, opacity: 0.9 }
        }).addTo(map);
      }).catch(function () {});
    }

    // City labels for orientation.
    CITIES.forEach(function (c) {
      L.marker([c[1], c[2]], {
        pane: "labels", interactive: false, keyboard: false,
        icon: L.divIcon({ className: "city t" + c[3], html: c[0].replace(/&/g, "&amp;").replace(/</g, "&lt;"), iconSize: null, iconAnchor: [3, 6] })
      }).addTo(map);
    });

    // Radar: the newest national composite, refreshed every five minutes.
    var radar = null;
    var loadRadar = function () {
      return fetch(IEM_META, { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (j) {
        var valid = new Date(j.meta.valid);
        if (isNaN(valid)) throw new Error("bad time");
        var stamp = valid.toISOString().replace(/[-:T]/g, "").slice(0, 12);
        var url = IEM_TILES + "ridge::USCOMP-N0Q-" + stamp + "/{z}/{x}/{y}.png";
        if (!radar) {
          radar = L.tileLayer(url, { pane: "radar", opacity: 0.85, maxNativeZoom: 8, maxZoom: 9 }).addTo(map);
        } else if (radar._url !== url) {
          radar.setUrl(url);
        }
        var t = valid.toLocaleTimeString([], { hour: "numeric", minute: "2-digit", timeZoneName: "short" });
        timeEl.innerHTML = "";
        var s = document.createElement("strong");
        s.textContent = "Radar from " + t;
        timeEl.appendChild(s);
        timeEl.appendChild(document.createTextNode(". Updates every 5 minutes."));
      }).catch(function () {
        if (!radar) timeEl.textContent = "Radar is taking a moment. The map will try again in a few minutes.";
      });
    };

    // Alerts drawn in the same colors the app uses.
    var isSevere = function (p) {
      return p.severity === "Extreme" || p.severity === "Severe" || /warning/i.test(p.event || "");
    };
    var untilText = function (p) {
      var end = p.ends || p.expires;
      if (!end) return "";
      var d = new Date(end);
      if (isNaN(d)) return "";
      return "Until " + d.toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit", timeZoneName: "short" });
    };
    var popupFor = function (p) {
      var box = document.createElement("div");
      var title = document.createElement("strong");
      title.textContent = p.event || "Weather alert";
      box.appendChild(title);
      if (p.areaDesc) {
        var where = document.createElement("p");
        where.className = "where";
        var a = p.areaDesc.split("; ");
        where.textContent = a.slice(0, 6).join(", ") + (a.length > 6 ? ", and " + (a.length - 6) + " more" : "");
        box.appendChild(where);
      }
      var u = untilText(p);
      if (u) {
        var until = document.createElement("p");
        until.className = "until";
        until.textContent = u;
        box.appendChild(until);
      }
      return box;
    };
    var alertsLayer = L.geoJSON(null, {
      pane: "alerts",
      style: function (f) {
        var c = isSevere(f.properties) ? "#ff6161" : "#f5b63f";
        return { color: c, weight: 2, opacity: 1, fillColor: c, fillOpacity: 0.18 };
      },
      onEachFeature: function (f, layer) { layer.bindPopup(popupFor(f.properties), { maxWidth: 260 }); }
    }).addTo(map);

    var plural = function (n, one, many) { return n + " " + (n === 1 ? one : many); };
    var loadAlerts = function () {
      var url = "https://api.weather.gov/alerts/active?status=actual&event=" + encodeURIComponent(EVENTS.join(","));
      return fetch(url, { headers: { Accept: "application/geo+json" } }).then(function (r) { return r.json(); }).then(function (j) {
        var feats = (j.features || []).filter(function (f) { return f.geometry; });
        alertsLayer.clearLayers();
        alertsLayer.addData({ type: "FeatureCollection", features: feats });
        var severe = feats.filter(function (f) { return isSevere(f.properties); }).length;
        nSevere.textContent = "(" + severe + ")";
        nOther.textContent = "(" + (feats.length - severe) + ")";
      }).catch(function () {});
    };

    // Earthquakes of magnitude 2.5 or more in the past day (U.S. Geological Survey).
    var quakeLayer = L.layerGroup().addTo(map);
    var loadQuakes = function () {
      return fetch("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson").then(function (r) { return r.json(); }).then(function (j) {
        quakeLayer.clearLayers();
        var n = 0;
        (j.features || []).forEach(function (f) {
          var c = f.geometry && f.geometry.coordinates;
          var p = f.properties || {};
          if (!c || typeof p.mag !== "number") return;
          if (c[1] < 15 || c[1] > 72 || c[0] < -180 || c[0] > -60) return;
          n++;
          var strong = p.mag >= 3;
          var box = document.createElement("div");
          var t = document.createElement("strong");
          t.textContent = "Magnitude " + p.mag.toFixed(1) + " earthquake";
          box.appendChild(t);
          var w = document.createElement("p");
          w.className = "where";
          w.textContent = p.place || "";
          box.appendChild(w);
          if (p.time) {
            var when = document.createElement("p");
            when.className = "until";
            when.textContent = new Date(p.time).toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit", timeZoneName: "short" });
            box.appendChild(when);
          }
          L.circleMarker([c[1], c[0]], {
            pane: "alerts", radius: 2 + Math.max(0, p.mag) * 1.5,
            color: "#ffffff", weight: 1, opacity: 0.8,
            fillColor: strong ? "#ff6161" : "#f59a33", fillOpacity: 0.75
          }).bindPopup(box, { maxWidth: 260 }).addTo(quakeLayer);
        });
        if (nQuakes) nQuakes.textContent = "(" + n + ")";
      }).catch(function () {});
    };

    var loadCount = function () {
      return fetch("https://api.weather.gov/alerts/active/count").then(function (r) { return r.json(); }).then(function (c) {
        if (typeof c.total !== "number") return;
        countEl.textContent = plural(c.total, "National Weather Service alert is", "National Weather Service alerts are") +
          " in effect across the U.S. right now, on land and at sea. Lookout shows you the ones for exactly where you are.";
      }).catch(function () {});
    };

    loadRadar();
    loadAlerts();
    loadQuakes();
    loadCount();
    setInterval(function () {
      if (document.hidden) return;
      loadRadar();
      loadAlerts();
      loadQuakes();
      loadCount();
    }, 5 * 60 * 1000);

    // Show my area: the browser asks first, and the position only moves the map.
    var you = null;
    if (meBtn) {
      if (!("geolocation" in navigator)) {
        meBtn.hidden = true;
      } else {
        meBtn.addEventListener("click", function () {
          meBtn.disabled = true;
          var meLabel = meBtn.querySelector("span");
          var old = meLabel.textContent;
          meLabel.textContent = "Finding you";
          navigator.geolocation.getCurrentPosition(function (pos) {
            var ll = [pos.coords.latitude, pos.coords.longitude];
            if (you) you.setLatLng(ll);
            else you = L.circleMarker(ll, { pane: "labels", radius: 7, color: "#0c1118", weight: 3, fillColor: "#f5b63f", fillOpacity: 1, interactive: false }).addTo(map);
            if (reduceMotion) map.setView(ll, 7); else map.flyTo(ll, 7, { duration: 1.2 });
            meBtn.disabled = false;
            meLabel.textContent = old;
            if (locNote) locNote.textContent = "Showing your area. Your location only moves this map; it isn't sent to us.";
          }, function () {
            meBtn.disabled = false;
            meLabel.textContent = old;
            if (locNote) locNote.textContent = "Location is off for this site, so the map stays put. You can drag or zoom to your area instead.";
          }, { enableHighAccuracy: false, timeout: 10000, maximumAge: 600000 });
        });
      }
    }
    if (allBtn) allBtn.addEventListener("click", function () { fit(true); });

    window.addEventListener("resize", function () { map.invalidateSize(); });
  }

  // Only load the map when it's about to scroll into view.
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      if (entries.some(function (e) { return e.isIntersecting; })) { io.disconnect(); start(); }
    }, { rootMargin: "300px 0px" });
    io.observe(mapEl);
  } else {
    start();
  }
  // Leaflet loads with defer; if it isn't there when needed, try again once it arrives.
  window.addEventListener("load", function () { if (started && !mapEl.classList.contains("leaflet-container")) { started = false; start(); } });
})();
