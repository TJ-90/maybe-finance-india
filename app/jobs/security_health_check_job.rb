class SecurityHealthCheckJob < ApplicationJob
  queue_as :scheduled

  def perform
    return unless MarketData.jobs_enabled?

    Security::HealthChecker.check_all
  end
end
