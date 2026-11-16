require "test_helper"

class Provider::GithubTest < ActiveSupport::TestCase
  test "defaults to the configured repo" do
    provider = Provider::Github.new

    assert_equal Rails.application.config.x.github_repo, "#{provider.owner}/#{provider.name}"
    assert_equal "TJ-90/maybe-finance-india", Rails.application.config.x.github_repo
  end

  test "release notes are nil without a repo and do not call GitHub" do
    Octokit.expects(:releases).never

    assert_nil Provider::Github.new(nil).fetch_latest_release_notes
  end
end
