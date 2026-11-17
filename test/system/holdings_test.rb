require "application_system_test_case"

class HoldingsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
    @user.update!(show_sidebar: true, show_ai_sidebar: true)
    @account = accounts(:investment)
  end

  test "value, return and XIRR are visible without sideways scrolling at 1440px with both sidebars open" do
    page.current_window.resize_to(1440, 900)
    visit account_path(@account, tab: "holdings")

    row = find("[data-testid='holding-value']", match: :first).find(:xpath, "..")
    assert row.has_css?("[data-testid='holding-return']")
    assert row.has_css?("[data-testid='holding-xirr']")

    result = page.evaluate_script(<<~JS)
      (function () {
        var row = document.querySelector("[data-testid='holding-value']").parentElement;
        var frame = row.closest("[data-testid='holdings-prices-as-of']") ? null : row.closest("div.bg-container-inset");
        var right = frame.getBoundingClientRect().right;
        var cells = ["holding-value", "holding-return", "holding-xirr"].map(function (id) {
          var rect = row.querySelector("[data-testid='" + id + "']").getBoundingClientRect();
          return { id: id, right: rect.right, width: rect.width };
        });
        return { containerRight: right, scrollOverflow: frame.scrollWidth - frame.clientWidth, cells: cells };
      })()
    JS

    assert_operator result["scrollOverflow"], :<=, 1, "holdings table scrolls sideways: #{result.inspect}"
    result["cells"].each do |cell|
      assert_operator cell["width"], :>, 0
      assert_operator cell["right"], :<=, result["containerRight"] + 1, "#{cell['id']} is cut off: #{result.inspect}"
    end
  end
end
