# frozen_string_literal: true

module RateLimit
  extend ActiveSupport::Concern

  # Note: Support for lambda with rails `rate_limit` is not yet released, so we have to support it by ourself
  # To remove when its fully supported by rails : https://github.com/rails/rails/commit/ac29e7d61cc93b832289120625633ac72635b552

  private

  def rate_limit(store: cache_store, name: nil)
    limit_name = "#{controller_name}_#{action_name}"
    window_name = "#{limit_name}_window"
    to = api_rate_limits&.dig(limit_name) || self.class::DEFAULT_RATE_LIMITS.dig(limit_name)
    within = (api_rate_limits&.dig(window_name) || self.class::DEFAULT_RATE_LIMITS.dig(limit_name)).seconds

    rate_limiting(
      to:,
      within:,
      by: -> { current_organization.id },
      with: -> { render_rate_limit_exceeded(within.to_i) },
      store: Rails.cache,
      name:
    )
  end
end
