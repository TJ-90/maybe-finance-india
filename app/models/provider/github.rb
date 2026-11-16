class Provider::Github
  attr_reader :name, :owner, :branch

  # Reads "owner/repo" from Rails.application.config.x.github_repo (ENV GITHUB_REPO)
  def initialize(repo = Rails.application.config.x.github_repo)
    @owner, @name = repo.to_s.split("/", 2)
    @branch = "main"
  end

  def fetch_latest_release_notes
    return nil if owner.blank? || name.blank?

    begin
      Rails.cache.fetch("latest_github_release_notes/#{repo}", expires_in: 2.hours) do
        release = Octokit.releases(repo).first
        if release
          {
            avatar: release.author.avatar_url,
            # this is the username, it would be nice to get the full name
            username: release.author.login,
            name: release.name,
            published_at: release.published_at,
            body: Octokit.markdown(release.body, mode: "gfm", context: repo)
          }
        else
          nil
        end
      end
    rescue => e
      Rails.logger.error "Failed to fetch latest GitHub release notes: #{e.message}"
      nil
    end
  end

  private
    def repo
      "#{owner}/#{name}"
    end
end
