# frozen_string_literal: true

# Creates the account tree values (users, teams, API keys...) reported by the events-processor.
# Every event goes through the events-processor, which stamps its attribution labels and reports
# each combination of a subscription and its labels at most once an hour per instance. Upserting
# is idempotent, so a combination reported by several instances, or a replayed batch, is harmless.
class UsageAttributionValuesConsumer < ApplicationConsumer
  def consume
    payloads = messages.map(&:payload).compact

    payloads.group_by { it["organization_id"] }.each do |organization_id, entries|
      track(organization_id, entries)
    end
  end

  private

  def track(organization_id, entries)
    organization = Organization.find_by(id: organization_id)
    return if organization.nil?
    return unless organization.account_tree_enabled? && organization.clickhouse_events_store?

    UsageAttributionValues::TrackService.call!(organization:, entries:)
  rescue => e
    Rails.logger.error("[usage_attribution_values] tracking failed organization_id=#{organization_id}: #{e.class} #{e.message}")
    Sentry.capture_exception(e, extra: {organization_id:})
  end
end
