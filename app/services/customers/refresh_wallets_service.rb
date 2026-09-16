# frozen_string_literal: true

module Customers
  class RefreshWalletsService < BaseService
    Result = BaseResult[:wallets]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices

      super
    end

    def call
      wallet_allocations = Wallets::Balance::AllocateOngoingUsageByWalletsService.call!(
        customer:,
        wallets: all_wallets,
        current_usage_fees:,
        draft_invoices_fees:,
        progressive_billing_fees:,
        pay_in_advance_fees:
      ).wallet_allocations

      # The cascade makes every wallet's allocation depend on the others' balances, so all
      # wallets must be persisted together; refreshing a subset would leave the rest stale.
      all_wallets.each do |wallet|
        Wallets::Balance::RefreshOngoingUsageService.call!(
          wallet:,
          ongoing_usage_amount_cents: wallet_allocations[wallet],
          skip_single_wallet_update: true
        )
      end

      Wallet.where(id: all_wallets.map(&:id)).touch_all(:last_ongoing_balance_sync_at) # rubocop:disable Rails/SkipsModelValidations

      customer.update!(awaiting_wallet_refresh: false)

      deliver_streaming_events

      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices

    def deliver_streaming_events
      streamed_event_types.each do |event_type|
        if event_type == StreamingDestinations::BaseDestination::CURRENT_USAGE_EVENT_TYPE && produce_inline?(event_type)
          produce_current_usage
        else
          DeliverEventJob.perform_after_commit(event_type, customer)
        end
      end
    end

    # Read once: the refresh asks which types are streamed, then asks twice more which destination
    # claims the current usage one, and every answer is a lookup in here. An event type is claimed
    # by a single destination, which the model validates, so one entry each.
    def destinations_by_event_type
      @destinations_by_event_type ||= StreamingDestinations::BaseDestination
        .where(organization: customer.organization, active: true)
        .flat_map { |destination| destination.event_types.map { [it, destination] } }
        .to_h
    end

    def streamed_event_types
      destinations_by_event_type
        .keys
        .intersection(StreamingDestinations::BaseDestination::EVENT_TYPES)
    end

    # The usage is already computed here, so the current-period record is produced from it rather
    # than paying for it again in a job. Deferred to after commit for the same reason the enqueue
    # is: Credits::AppliedPrepaidCreditsService refreshes inside a transaction and a customer lock,
    # and a rolled back refresh must not reach the stream.
    def produce_current_usage
      event_type = StreamingDestinations::BaseDestination::CURRENT_USAGE_EVENT_TYPE

      after_commit do
        EventDestinations::CustomerUsage::RefreshedService.call(object: customer, usages: computed_usages)

        # The producer swallows a credentials failure into a dropped log, so without this the event
        # would be lost on a worker that cannot assume the destination role.
        DeliverEventJob.perform_later(event_type, customer) unless produce_inline?(event_type)
      rescue => e
        EventDestinations::DeliveryLogger.emit(
          :failed,
          event_type:,
          customer_id: customer.id,
          error: e.class,
          message: e.message
        )

        DeliverEventJob.perform_later(event_type, customer)
      end
    end

    def computed_usages
      subscription_usages.to_h { [it[:subscription], it[:usage]] }
    end

    # Only a worker holds the AWS identity the producer needs, and only until it proves otherwise:
    # a process that has already failed to obtain credentials stops paying the STS timeout and
    # hands the delivery to the streaming worker instead.
    def produce_inline?(event_type)
      return false unless Sidekiq.server?

      destination = destinations_by_event_type[event_type]
      return false if destination.nil?

      Lago::Kinesis::Producer.credentials_available?(destination)
    end

    def all_wallets
      @all_wallets ||= customer.wallets.active.includes(:recurring_transaction_rules, :wallet_targets).in_application_order.to_a
    end

    def current_usage_fees
      @current_usage_fees ||= subscription_usages.flat_map { |usage| usage[:invoice].fees }
    end

    # Must be a subset of current_usage_fees so both buckets share fee keys and net out.
    def pay_in_advance_fees
      current_usage_fees.select { |fee| fee.charge.pay_in_advance? }
    end

    def draft_invoices_fees
      customer.invoices.draft.where.not(total_amount_cents: 0).includes(fees: :charge).flat_map(&:fees)
    end

    def progressive_billing_fees
      subscription_usages.flat_map { |usage| usage[:billed_progressive_invoice_subscriptions].flat_map { it.invoice.fees.includes(:charge) } }
    end

    # One entry per active subscription: its current-usage invoice and the progressively
    # billed invoice subscriptions used to net already-billed amounts out of ongoing usage.
    def subscription_usages
      @subscription_usages ||= customer.active_subscriptions.map do |subscription|
        usage_result = ::Invoices::CustomerUsageService.call!(customer:, subscription:, usage_filters: UsageFilters::WITHOUT_PRESENTATION_FILTER)

        billed_progressive_invoice_subscriptions = ::Subscriptions::ProgressiveBilledAmount
          .call(subscription:, include_generating_invoices:)
          .invoice_subscriptions

        {billed_progressive_invoice_subscriptions:, invoice: usage_result.invoice, usage: usage_result.usage, subscription:}
      end
    end
  end
end
