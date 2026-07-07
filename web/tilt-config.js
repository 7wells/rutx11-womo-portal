// Vehicle geometry and sensor orientation. Adjust these values after verification.
window.WOMO_TILT_CONFIG = Object.freeze({
  wheelbaseMm: 4035,
  frontTrackMm: 1810,
  rearTrackMm: 1790,
  longitudinal: { source: 'roll', factor: -1 },
  transverse: { source: 'pitch', factor: 1 }
});
