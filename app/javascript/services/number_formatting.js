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
export function formatCompactAmount(value, { currency = "USD", symbol = "" } = {}) {
  const sign = value < 0 ? "-" : "";
  const abs = Math.abs(value);
  const trim = (n, digits) => Number(n.toFixed(digits)).toString();

  let text;
  if (currency === "INR") {
    if (abs >= INR_CRORE) text = `${(abs / INR_CRORE).toFixed(2)} Cr`;
    else if (abs >= INR_LAKH) text = `${(abs / INR_LAKH).toFixed(2)} L`;
    else if (abs >= 1000) text = `${trim(abs / 1000, 1)}K`;
    else text = trim(abs, 0);
  } else if (abs >= 1e9) text = `${(abs / 1e9).toFixed(2)}B`;
  else if (abs >= 1e6) text = `${(abs / 1e6).toFixed(2)}M`;
  else if (abs >= 1000) text = `${trim(abs / 1000, 1)}K`;
  else text = trim(abs, 0);

  return `${sign}${symbol}${text}`;
}
