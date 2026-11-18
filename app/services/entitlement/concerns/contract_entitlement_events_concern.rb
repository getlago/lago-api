# frozen_string_literal: true

module Entitlement
  module Concerns
    # The contract_entitlement.* activity logs and webhooks of the services that write contract entitlements, so that
    # every write sends the same render. Only sent with the entitlement_events feature flag.
    module ContractEntitlementEventsConcern
      extend ActiveSupport::Concern

      private

      # The events need the contract entitlements rendered before the write, so the render is only built when one of
      # them can be sent.
      def render_contract_entitlement_events?(contract)
        contract.organization.feature_flag_enabled?(:entitlement_events) &&
          (Utils::ActivityLog.available? || send_contract_entitlement_webhooks?(contract))
      end

      # The jobs are enqueued in one bulk push, which skips the endpoint check of SendWebhookJob.perform_later.
      def send_contract_entitlement_webhooks?(contract)
        return @send_contract_entitlement_webhooks if defined?(@send_contract_entitlement_webhooks)

        @send_contract_entitlement_webhooks = contract.organization.webhook_endpoints.exists?
      end

      def render_contract_entitlement(contract_entitlement)
        ::V2::ContractEntitlementSerializer.new(contract_entitlement).serialize
      end

      # One activity log and one webhook per change, in the given order. A change is the render before and the render
      # after the write (nil when the entitlement did not apply). A removed entitlement is sent as it applied before.
      def send_contract_entitlement_events(contract, changes)
        webhook_jobs = changes.filter_map do |before, after|
          action = if before.nil?
            "created"
          elsif after.nil?
            "deleted"
          else
            "updated"
          end
          render = after || before

          if Utils::ActivityLog.available?
            Utils::ActivityLog.produce_after_commit(
              contract, "contract_entitlement.#{action}",
              activity_object: render,
              changes: {"values" => [before&.dig(:values), after&.dig(:values)]}
            )
          end
          next unless send_contract_entitlement_webhooks?(contract)

          SendWebhookJob.new("contract_entitlement.#{action}", contract, {contract_entitlement: render})
        end

        after_commit { ApplicationJob.perform_all_later(webhook_jobs) } if webhook_jobs.any?
      end
    end
  end
end
