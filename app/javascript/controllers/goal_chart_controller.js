import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

const parseLocalDate = d3.timeParse("%Y-%m-%d");

// Two-line chart for a goal: projected corpus against the inflation-adjusted target. All text shown
// to the user (dates, money) is formatted on the server and arrives in the data; only axis ticks are
// formatted here.
export default class extends Controller {
  static values = {
    data: Object,
    currency: { type: String, default: "INR" },
  };

  _points = [];
  _resizeObserver = null;

  connect() {
    this._draw();
    this._resizeObserver = new ResizeObserver(() => this._draw());
    this._resizeObserver.observe(this.element);
  }

  disconnect() {
    this._resizeObserver?.disconnect();
    d3.select(this.element).selectAll("*").remove();
  }

  _draw() {
    const container = d3.select(this.element);
    container.selectAll("*").remove();

    this._points = (this.dataValue.points || []).map((point) => ({
      ...point,
      date: parseLocalDate(point.date),
    }));

    const width = this.element.clientWidth;
    const height = this.element.clientHeight;

    if (this._points.length < 2 || width === 0) return;

    const margin = { top: 8, right: 8, bottom: 24, left: 56 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const svg = container
      .append("svg")
      .attr("width", width)
      .attr("height", height);
    const group = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const x = d3
      .scaleTime()
      .domain(d3.extent(this._points, (d) => d.date))
      .range([0, innerWidth]);
    const maxValue = d3.max(this._points, (d) =>
      Math.max(d.projected, d.target),
    );
    const y = d3
      .scaleLinear()
      .domain([0, maxValue * 1.05])
      .range([innerHeight, 0]);

    group
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(d3.axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 90))))
      .call((g) => g.select(".domain").attr("stroke", "currentColor"))
      .selectAll("text")
      .attr("class", "fg-gray")
      .style("font-size", "11px");

    group
      .append("g")
      .call(
        d3
          .axisLeft(y)
          .ticks(5)
          .tickSize(-innerWidth)
          .tickFormat((value) => this._formatTick(value)),
      )
      .call((g) => g.select(".domain").remove())
      .call((g) =>
        g
          .selectAll(".tick line")
          .attr("stroke", "currentColor")
          .attr("stroke-opacity", 0.08),
      )
      .selectAll("text")
      .attr("class", "fg-gray")
      .style("font-size", "11px");

    this._line(group, x, y, "target", "var(--color-gray-400)", "4,4");
    this._line(group, x, y, "projected", "var(--color-green-600)");

    this._drawTooltip(group, x, y, innerWidth, innerHeight);
  }

  _line(group, x, y, key, color, dash) {
    const path = group
      .append("path")
      .datum(this._points)
      .attr("fill", "none")
      .attr("stroke", color)
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr(
        "d",
        d3
          .line()
          .x((d) => x(d.date))
          .y((d) => y(d[key])),
      );

    if (dash) path.attr("stroke-dasharray", dash);
  }

  _drawTooltip(group, x, y, innerWidth, innerHeight) {
    const tooltip = d3
      .select(this.element)
      .style("position", "relative")
      .append("div")
      .attr(
        "class",
        "bg-container text-sm font-sans absolute p-2 border border-secondary rounded-lg pointer-events-none opacity-0",
      )
      .style("z-index", 999);

    const guideline = group
      .append("line")
      .attr("y1", 0)
      .attr("y2", innerHeight)
      .attr("stroke", "currentColor")
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0);

    const bisect = d3.bisector((d) => d.date).center;

    group
      .append("rect")
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .on("mousemove", (event) => {
        const [xPos] = d3.pointer(event);
        const point = this._points[bisect(this._points, x.invert(xPos))];
        const left = Math.min(x(point.date) + 64, this.element.clientWidth - 180);

        guideline
          .attr("x1", x(point.date))
          .attr("x2", x(point.date))
          .attr("opacity", 0.4);
        tooltip
          .style("opacity", 1)
          .style("left", `${left}px`)
          .style("top", "8px")
          .html(this._tooltipHtml(point));
      })
      .on("mouseout", () => {
        guideline.attr("opacity", 0);
        tooltip.style("opacity", 0);
      });
  }

  _tooltipHtml(point) {
    return `
      <div style="margin-bottom: 4px; color: var(--color-gray-500);">${point.date_formatted}</div>
      <div class="text-primary">Projected: ${point.projected_formatted}</div>
      <div class="text-secondary">Target: ${point.target_formatted}</div>
    `;
  }

  _formatTick(value) {
    if (value === 0) return "0";

    if (this.currencyValue === "INR") {
      if (value >= 1e7) return `${this._trim(value / 1e7)} Cr`;
      if (value >= 1e5) return `${this._trim(value / 1e5)} L`;
      if (value >= 1e3) return `${this._trim(value / 1e3)}K`;
      return `${value}`;
    }

    return new Intl.NumberFormat("en", { notation: "compact" }).format(value);
  }

  _trim(number) {
    return Number(number.toFixed(2)).toString();
  }
}
