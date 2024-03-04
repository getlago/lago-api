# frozen_string_literal: true

module TimebasedEvents
  module SubscriptionRenewals
    class CreateService < BaseService
      def initialize(event, sync: false)
        @event = event
        @sync = sync
        super(nil)
      end

      def call
        timebased_event = build_timebased_event
        timebased_event.save!

        process_renewal
        result.timebased_event = timebased_event
        result
      end

      def process_event?
        return false if already_renewed_subscription?

        matching_charge? && matching_billable_metric? && block_time_elapsed?
      end

      private

      attr_accessor :event, :sync

      delegate :subscription, :organization, to: :event
      delegate :plan, to: :subscription

      def matching_charge?
        return false if matching_charge.blank?

        matching_charge.properties&.fetch('usage') == 'subscription_renewal' &&
          block_time_in_minutes.positive?
      end

      def matching_billable_metric?
        matching_billable_metric&.usage_time_agg?
      end

      def block_time_elapsed?
        latest_subscription_renewal_event_within_block_time(block_time_in_minutes).blank?
      end

      def latest_subscription_renewal_event_within_block_time(block_time_in_minutes)
        @latest_subscription_renewal_event_within_block_time ||= TimebasedEvent
          .where(organization_id: organization.id)
          .where(external_subscription_id: subscription.external_id)
          .where(event_type: TimebasedEvent.event_types[:subscription_renewal])
          .where('timestamp >= ?', event.timestamp - block_time_in_minutes.minutes)
          .order(timestamp: :desc)
          .first
      end

      def build_timebased_event
        TimebasedEvent.new(
          organization:,
          external_customer_id: event.external_customer_id,
          external_subscription_id: event.external_subscription_id,
          billable_metric_id: matching_billable_metric.id,
          metadata: event.metadata,
          timestamp: Time.zone.at(event.timestamp),
          event_type: :subscription_renewal,
        )
      end

      def matching_charge
        @matching_charge ||= Charge
          .where(
            plan_id: plan.id,
            charge_model: 'timebased',
          )
          .where('properties->>\'usage\' = ?', 'subscription_renewal')
          .first
      end

      def block_time_in_minutes
        matching_charge.properties&.fetch('block_time_in_minutes')
      end

      def process_renewal
        if sync
          renewal_result = Invoices::CreatePayInAdvanceSyncChargeJob
            .perform_now(charge: matching_charge, event:, timestamp: event.timestamp)

          renewal_result unless renewal_result.success?
          return
        end

        Invoices::CreatePayInAdvanceChargeJob
          .perform_later(charge: matching_charge, event:, timestamp: event.timestamp)
      end

      def matching_billable_metric
        @matching_billable_metric ||= matching_charge&.billable_metric
      end

      def already_renewed_subscription?
        # TODO: should compare in the same timezone
        InvoiceSubscription
          .where(subscription:)
          .where(
            'from_datetime <= ? AND to_datetime >= ?', event.timestamp, event.timestamp
          ).exists?
      end
    end
  end
end
