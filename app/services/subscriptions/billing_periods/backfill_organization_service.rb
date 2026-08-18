# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Fills in the periods of subscriptions that predate this table. Run per organization, out of
    # band. Idempotent, so it is safe to re-run.
    class BackfillOrganizationService < BaseService
      Result = BaseResult[:processed_count, :failed_count]

      def initialize(organization:, batch_size: 1_000)
        @organization = organization
        @batch_size = batch_size

        super
      end

      def call
        processed = 0
        failed = 0

        organization.subscriptions.active.includes(:plan, :customer).find_each(batch_size:) do |subscription|
          Subscriptions::BillingPeriods::UpsertService.call!(subscription:)
          processed += 1
        rescue => e
          failed += 1
          Sentry.capture_exception(e, extra: {subscription_id: subscription.id})
        end

        result.processed_count = processed
        result.failed_count = failed
        result
      end

      private

      attr_reader :organization, :batch_size
    end
  end
end
