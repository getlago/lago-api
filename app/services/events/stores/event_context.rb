# frozen_string_literal: true

module Events
  module Stores
    class EventContext
      def self.from(subscription: nil, contract: nil)
        if subscription.present? && contract.present?
          raise ArgumentError, "subscription or contract is required"
        end

        new(subscription:, contract:)
      end

      def initialize(subscription: nil, contract: nil)
        if [subscription, contract].compact.one?
          @record = subscription || contract
        else
          raise ArgumentError, "subscription or contract is required"
        end
      end

      delegate :external_id,
        :organization,
        :organization_id,
        :customer,
        :plan,
        :started_at,
        :terminated_at,
        :terminated?,
        :terminated_at?,
        :date_diff_with_timezone,
        :calendar?,
        :anniversary?,
        to: :record

      def id
        return record.id if subscription?

        raise NotImplementedError, "contract-backed event contexts do not have a subscription id"
      end

      def subscription_at
        return record.subscription_at if subscription?

        record.started_at
      end

      def invoice_subscriptions
        return record.invoice_subscriptions if subscription?

        raise_contract_context_not_supported(:invoice_subscriptions)
      end

      def previous_subscription
        return record.previous_subscription if subscription?

        raise_contract_context_not_supported(:previous_subscription)
      end

      def previous_subscription_id
        return record.previous_subscription_id if subscription?

        raise_contract_context_not_supported(:previous_subscription_id)
      end

      def previous_subscription_id?
        return previous_subscription_id.present? if subscription?

        raise_contract_context_not_supported(:previous_subscription_id?)
      end

      def next_subscription
        return record.next_subscription if subscription?

        raise_contract_context_not_supported(:next_subscription)
      end

      def upgraded?
        return record.upgraded? if subscription?

        raise_contract_context_not_supported(:upgraded?)
      end

      def downgraded?
        return record.downgraded? if subscription?

        raise_contract_context_not_supported(:downgraded?)
      end

      def charges_duration_at(billing_at)
        unless subscription?
          raise NotImplementedError, "contract-backed event contexts do not have charge durations yet"
        end

        Subscriptions::DatesService.new_instance(
          record,
          billing_at,
          current_usage: terminated? && upgraded?
        ).charges_duration_in_days
      end

      private

      attr_reader :record

      def subscription?
        record.is_a?(::Subscription)
      end

      def raise_contract_context_not_supported(method_name)
        raise NotImplementedError, "contract-backed event contexts do not have #{method_name} yet"
      end
    end
  end
end
