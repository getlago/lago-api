# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceJob < ApplicationJob
    queue_as :default

    # Random jitter (in seconds) added to every retry so parallel failed jobs
    # don't retry in lockstep and overload Clickhouse again at the same instant.
    RETRY_JITTER = 1..15

    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

    # Increasing backoff (a few seconds, then longer and longer) plus jitter, to give
    # Clickhouse time to recover from too many high-usage parallel calls.
    retry_on Events::Stores::Clickhouse::MemoryLimitError,
      wait: ->(executions) { Fees::CreatePayInAdvanceJob.retry_wait(executions) },
      attempts: 25

    def self.retry_wait(executions)
      (executions**4) + rand(RETRY_JITTER)
    end

    unique :until_executed, on_conflict: :log

    def perform(charge: nil, metered_item: nil, event: nil, billing_at: nil)
      resolved_metered_item = pay_in_advance_arguments.metered_item
      billing_context = pay_in_advance_arguments.billing_context

      unless billing_context
        skip_missing_billing_context(
          metered_item: resolved_metered_item,
          timestamp: billing_at || resolved_metered_item.event.timestamp
        )
        return
      end

      result = Fees::CreatePayInAdvanceService.call(
        metered_item: resolved_metered_item,
        billing_context:,
        billing_at:
      )

      return if !result.success? && tax_error?(result)

      result.raise_if_error!
    end

    delegate :lock_key_arguments, to: :pay_in_advance_arguments

    private

    def pay_in_advance_arguments
      @pay_in_advance_arguments ||= PayInAdvanceArguments.new(
        metered_item: arguments.first.with_indifferent_access[:metered_item],
        charge: arguments.first.with_indifferent_access[:charge],
        event: arguments.first.with_indifferent_access[:event]
      )
    end

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error).present?
    end

    def skip_missing_billing_context(metered_item:, timestamp:)
      event = metered_item.event
      message = "Fees::CreatePayInAdvanceJob skipped: no billing context for event"
      context = {
        organization_id: event.organization_id,
        external_subscription_id: event.external_subscription_id,
        event_transaction_id: event.transaction_id,
        event_timestamp: timestamp.iso8601
      }.merge(
        if metered_item.billing_segment
          {billing_segment_id: metered_item.billing_segment.id}
        else
          {charge_id: metered_item.charge.id}
        end
      )

      Rails.logger.error("#{message} #{context.map { |key, value| "#{key}=#{value}" }.join(" ")}")
    end
  end
end
