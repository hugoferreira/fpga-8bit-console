
function rgbto565(r, g, b) {
  const r565 = Math.round((r * (2 ** 5 - 1)) / (2 ** 8 - 1)).toString(2).padStart(5, '0');
  const g565 = Math.round((g * (2 ** 6 - 1)) / (2 ** 8 - 1)).toString(2).padStart(6, '0');
  const b565 = Math.round((b * (2 ** 5 - 1)) / (2 ** 8 - 1)).toString(2).padStart(5, '0');
  return `16'b${r565}${g565}${b565}`
}

rgbto565(0, 0, 0) //?
rgbto565(29, 43, 83) //?
rgbto565(126, 37, 83) //?
rgbto565(0, 135, 81) //?
rgbto565(171, 82, 54) //?
rgbto565(95, 87, 79) //?
rgbto565(194, 195, 199) //?
rgbto565(255, 241, 232) //?
rgbto565(255, 0, 77) //?
rgbto565(255, 163, 0) //?
rgbto565(255, 236, 39) //?
rgbto565(0, 228, 54) //?
rgbto565(41, 173, 255) //?
rgbto565(131, 118, 156) //?
rgbto565(255, 119, 168) //?
rgbto565(255, 204, 170) //?
