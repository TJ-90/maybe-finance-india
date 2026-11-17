import { Controller } from "@hotwired/stimulus";

// Shows only the fields and help text that apply to the selected AI provider
export default class extends Controller {
  static targets = ["radio", "panel", "chatModel", "fastModel", "suggestions"];
  static values = { defaults: Object, suggestions: Object };

  connect() {
    this.update();
  }

  update() {
    const provider = this.selectedProvider();

    this.panelTargets.forEach((panel) => {
      const providers = panel.dataset.providers.split(" ");
      panel.classList.toggle("hidden", !providers.includes(provider));
    });

    const defaults = this.defaultsValue[provider] || {};
    this.chatModelTarget.placeholder = defaults.chat || "Required";
    this.fastModelTarget.placeholder = defaults.fast || "Required";

    const options = this.suggestionsValue[provider] || [];
    this.suggestionsTarget.innerHTML = "";
    options.forEach((name) => {
      const option = document.createElement("option");
      option.value = name;
      this.suggestionsTarget.appendChild(option);
    });
  }

  selectedProvider() {
    const checked = this.radioTargets.find((radio) => radio.checked);
    return checked ? checked.value : "openai";
  }
}
