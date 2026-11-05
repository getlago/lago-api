# frozen_string_literal: true

# Creates the account tree values (users, teams, API keys...) reported by the events-processor.
# Every event goes through the events-processor, which stamps its attribution labels and reports
# each combination of a subscription and its labels at most once an hour per instance. Upserting
# is idempotent, so a combination reported by several instances, or a replayed batch, is harmless.
class UsageAttributionValuesConsumer < ApplicationConsumer
  MAX_ATTEMPTS = 3

  TRANSIENT_ERRORS = [
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::ConnectionTimeoutError,
    ActiveRecord::QueryCanceled,
    ActiveRecord::LockWaitTimeout,
    ActiveRecord::Deadlocked
  ].freeze

  def consume
    payloads = messages.filter_map { parse(it) }

    failures = payloads.group_by { it["organization_id"] }.filter_map do |organization_id, entries|
      track(organization_id, entries)
    end
    return if failures.empty?

    raise failures.first[:error] if attempt < MAX_ATTEMPTS

    failures.each { UsageAttributionValues::TrackJob.perform_later(it[:organization_id], it[:entries]) }
  end

  private

  def parse(message)
    payload = message.payload
    payload if payload.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def track(organization_id, entries)
    organization = Organization.find_by(id: organization_id)
    UsageAttributionValues::TrackService.call!(organization:, entries:) if organization
    nil
  rescue *TRANSIENT_ERRORS => e
    Rails.logger.warn("[usage_attribution_values] tracking failed organization_id=#{organization_id} attempt=#{attempt}: #{e.class} #{e.message}")
    {organization_id:, entries:, error: e}
  rescue => e
    Rails.logger.error("[usage_attribution_values] tracking failed organization_id=#{organization_id}: #{e.class} #{e.message}")
    Sentry.capture_exception(e, extra: {organization_id:})
    nil
  end
end
