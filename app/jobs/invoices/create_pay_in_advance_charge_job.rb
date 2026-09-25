# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75
    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

    retry_on BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    # DEPRECATED: These errors should not be raised anymore but we keep them and monitor to be sure.
    retry_on ActiveRecord::LockWaitTimeout, PG::LockNotAvailable, queue: :low_priority, wait: :polynomially_longer, attempts: 15

    unique :until_executed, on_conflict: :log

    def perform(timestamp:, charge: nil, metered_item: nil, event: nil, invoice: nil)
      resolved_metered_item = pay_in_advance_arguments.metered_item
      billing_context = pay_in_advance_arguments.billing_context

      unless billing_context
        skip_missing_billing_context(metered_item: resolved_metered_item, timestamp: Time.zone.at(timestamp))
        return
      end

      result = Invoices::CreatePayInAdvanceChargeService.call(
        metered_item: resolved_metered_item,
        billing_context:,
        timestamp:
      )
      return if result.success?
      # NOTE: We don't want a dead job for failed invoice due to the tax reason.
      #       This invoice should be in failed status and can be retried.
      return if tax_error?(result)

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
      message = "Invoices::CreatePayInAdvanceChargeJob skipped: no billing context for event"
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
