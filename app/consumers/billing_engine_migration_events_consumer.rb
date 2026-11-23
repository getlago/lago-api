# frozen_string_literal: true

# Copies the events of organizations whose migration reads them from the raw events topic to their
# shadow organization. A failed copy raises, so the batch is retried from its first offset instead
# of being acknowledged without its copies.
class BillingEngineMigrationEventsConsumer < ApplicationConsumer
  def consume
    report_lag

    migrations = BillingEngineMigrations::Lookup.copying_events_from(BillingEngineMigration::EVENTS_COPY_SOURCES[:raw_topic])
    return if migrations.empty?

    result = BillingEngineMigrations::CopyRawEventsService.call!(migrations:, raw_payloads: messages.map(&:raw_payload))
    report_outcomes(result)
  rescue => e
    report_failure(e)
    raise
  end

  private

  def report_lag
    Yabeda.billing_engine_migrations.events_copy_lag.measure({}, Time.current - messages.last.timestamp)
  end

  def report_outcomes(result)
    {copied: result.copied_count, unmapped: result.unmapped_count, invalid: result.invalid_count}.each do |outcome, count|
      Yabeda.billing_engine_migrations.events_copy_total.increment({outcome: outcome.to_s}, by: count) if count.positive?
    end
  end

  def report_failure(error)
    Yabeda.billing_engine_migrations.events_copy_failures_total.increment({})
    Rails.logger.error(
      "[billing_engine_migrations] events copy failed partition=#{messages.metadata.partition} " \
      "offsets=#{messages.first.offset}..#{messages.last.offset} attempt=#{attempt}: #{error.class} #{error.message}"
    )
  end
end
