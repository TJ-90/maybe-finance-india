module SettingsHelper
  SETTINGS_ORDER = [
    { name: "Account", path: :settings_profile_path },
    { name: "Preferences", path: :settings_preferences_path },
    { name: "Security", path: :settings_security_path },
    { name: "Self hosting", path: :settings_hosting_path, condition: :self_hosted? },
    { name: "API Key", path: :settings_api_key_path },
    { name: "Market data", path: :settings_market_data_path },
    { name: "Notifications", path: :settings_notifications_path },
    { name: "AI", path: :settings_ai_provider_path, condition: :ai_settings_visible? },
    { name: "Billing", path: :settings_billing_path, condition: :billing_visible? },
    { name: "Accounts", path: :accounts_path },
    { name: "Imports", path: :imports_path },
    { name: "Tags", path: :tags_path },
    { name: "Categories", path: :categories_path },
    { name: "Rules", path: :rules_path },
    { name: "Merchants", path: :family_merchants_path },
    { name: "What's new", path: :changelog_path, condition: :github_repo_configured? },
    { name: "Feedback", path: :feedback_path, condition: :github_repo_configured? }
  ]

  def adjacent_setting(current_path, offset)
    visible_settings = SETTINGS_ORDER.select { |setting| setting[:condition].nil? || send(setting[:condition]) }
    current_index = visible_settings.index { |setting| send(setting[:path]) == current_path }
    return nil unless current_index

    adjacent_index = current_index + offset
    return nil if adjacent_index < 0 || adjacent_index >= visible_settings.size

    adjacent = visible_settings[adjacent_index]

    render partial: "settings/settings_nav_link_large", locals: {
      path: send(adjacent[:path]),
      direction: offset > 0 ? "next" : "previous",
      title: adjacent[:name]
    }
  end

  def settings_section(title:, subtitle: nil, &block)
    content = capture(&block)
    render partial: "settings/section", locals: { title: title, subtitle: subtitle, content: content }
  end

  def settings_nav_footer
    previous_setting = adjacent_setting(request.path, -1)
    next_setting = adjacent_setting(request.path, 1)

    content_tag :div, class: "hidden md:flex flex-row justify-between gap-4" do
      concat(previous_setting)
      concat(next_setting)
    end
  end

  def settings_nav_footer_mobile
    previous_setting = adjacent_setting(request.path, -1)
    next_setting = adjacent_setting(request.path, 1)

    content_tag :div, class: "md:hidden flex flex-col gap-4" do
      concat(previous_setting)
      concat(next_setting)
    end
  end

  private
    def ai_settings_visible?
      Current.user&.admin?
    end

    def billing_visible?
      !self_hosted? && stripe_configured?
    end
end
