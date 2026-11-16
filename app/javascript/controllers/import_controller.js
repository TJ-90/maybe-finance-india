import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="import"
export default class extends Controller {
  static values = {
    csv: { type: Array, default: [] },
    amountTypeColumnKey: { type: String, default: "" },
  };

  static targets = [
    "signedAmountFieldset",
    "customColumnFieldset",
    "amountTypeValue",
    "amountTypeStrategySelect",
    "debitCreditFieldset",
    "amountColumnSelect",
  ];

  connect() {
    if (this.hasDebitCreditFieldsetTarget) {
      this.#toggleAmountColumn(
        this.amountTypeStrategySelectTarget.value !== "debit_credit_columns",
      );
    }

    if (
      this.amountTypeStrategySelectTarget.value === "custom_column" &&
      this.amountTypeColumnKeyValue
    ) {
      this.#showAmountTypeValueTargets(this.amountTypeColumnKeyValue);
    }
  }

  handleAmountTypeStrategyChange(event) {
    const amountTypeStrategy = event.target.value;

    this.#showFieldset(
      this.signedAmountFieldsetTarget,
      amountTypeStrategy === "signed_amount",
    );
    this.#showFieldset(
      this.customColumnFieldsetTarget,
      amountTypeStrategy === "custom_column",
    );
    this.#showFieldset(
      this.debitCreditFieldsetTarget,
      amountTypeStrategy === "debit_credit_columns",
    );

    // Separate debit/credit columns replace the single amount column
    this.#toggleAmountColumn(amountTypeStrategy !== "debit_credit_columns");

    if (
      amountTypeStrategy === "custom_column" &&
      this.amountTypeColumnKeyValue
    ) {
      this.#showAmountTypeValueTargets(this.amountTypeColumnKeyValue);
    }
  }

  handleAmountTypeChange(event) {
    const amountTypeColumnKey = event.target.value;

    this.#showAmountTypeValueTargets(amountTypeColumnKey);
  }

  #showAmountTypeValueTargets(amountTypeColumnKey) {
    const selectableValues = this.#uniqueValuesForColumn(amountTypeColumnKey);

    this.amountTypeValueTarget.classList.remove("hidden");
    this.amountTypeValueTarget.classList.add("flex");

    const select = this.amountTypeValueTarget.querySelector("select");
    const currentValue = select.value;
    select.options.length = 0;
    const fragment = document.createDocumentFragment();

    // Only add the prompt if there's no current value
    if (!currentValue) {
      fragment.appendChild(new Option("Select value", ""));
    }

    selectableValues.forEach((value) => {
      const option = new Option(value, value);
      if (value === currentValue) {
        option.selected = true;
      }
      fragment.appendChild(option);
    });

    select.appendChild(fragment);
  }

  #uniqueValuesForColumn(column) {
    const colIdx = this.csvValue[0].indexOf(column);
    const values = this.csvValue.slice(1).map((row) => row[colIdx]);
    return [...new Set(values)];
  }

  #showFieldset(fieldset, visible) {
    fieldset.classList.toggle("hidden", !visible);
    fieldset.classList.toggle("block", visible);

    fieldset.querySelectorAll("select, input").forEach((field) => {
      if (visible) {
        field.setAttribute("required", "");
      } else {
        field.removeAttribute("required");
      }
    });
  }

  #toggleAmountColumn(visible) {
    if (!this.hasAmountColumnSelectTarget) return;

    const select = this.amountColumnSelectTarget;
    const container = select.closest(".form-field") || select;

    container.classList.toggle("hidden", !visible);

    if (visible) {
      select.setAttribute("required", "");
    } else {
      select.removeAttribute("required");
    }
  }
}
