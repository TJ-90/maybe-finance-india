// Chart-side number formatting. Currency values shown in the page are formatted on the server;
// this exists only for values that must be computed in the browser (chart tooltips and axis ticks).

const INR_LAKH = 100000;
const INR_CRORE = 10000000;

export function formatAmount(value, { currency = "USD", symbol = "" } = {}) {
  const locale = currency === "INR" ? "en-IN" : undefined;
  const number = Number.parseFloat(value).toLocaleString(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });

  return `${symbol}${number}`;
}

// Compact tick labels: K / L / Cr for INR (lakh, crore) and K / M / B otherwise.
// A value that rounds up to the next unit's size moves to that unit (999,999.999 is "1.00M", not "1000K").
const trim = (n, digits) => Number(n.toFixed(digits)).toString();
const fixed = (n) => n.toFixed(2);

const INR_SCALES = [
  { divisor: 1, suffix: "", digits: 0, format: (n) => trim(n, 0) },
  { divisor: 1000, suffix: "K", digits: 1, format: (n) => trim(n, 1) },
  { divisor: INR_LAKH, suffix: " L", digits: 2, format: fixed },
  { divisor: INR_CRORE, suffix: " Cr", digits: 2, format: fixed }
];

const INTERNATIONAL_SCALES = [
  { divisor: 1, suffix: "", digits: 0, format: (n) => trim(n, 0) },
  { divisor: 1000, suffix: "K", digits: 1, format: (n) => trim(n, 1) },
  { divisor: 1e6, suffix: "M", digits: 2, format: fixed },
  { divisor: 1e9, suffix: "B", digits: 2, format: fixed }
];

export function formatCompactAmount(value, { currency = "USD", symbol = "" } = {}) {
  const sign = value < 0 ? "-" : "";
  const abs = Math.abs(value);
  const scales = currency === "INR" ? INR_SCALES : INTERNATIONAL_SCALES;

  let index = 0;
  scales.forEach((scale, i) => {
    if (abs >= scale.divisor) index = i;
  });

  while (index + 1 < scales.length) {
    const scale = scales[index];
    const rounded = Number((abs / scale.divisor).toFixed(scale.digits)) * scale.divisor;
    if (rounded < scales[index + 1].divisor) break;
    index += 1;
  }

  const scale = scales[index];
  return `${sign}${symbol}${scale.format(abs / scale.divisor)}${scale.suffix}`;
}
