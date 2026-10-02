# frozen_string_literal: true

module Billing
  class Context
    def self.from(subscription: nil, contract: nil)
      new(subscription:, contract:)
    end

    def initialize(subscription: nil, contract: nil)
      if [subscription, contract].compact.one?
        @record = subscription || contract
      else
        raise ArgumentError, "exactly one of subscription or contract is required"
      end
    end

    delegate :external_id,
      :applicable_billing_entity_id,
      :billing_entity,
      :organization,
      :organization_id,
      :customer,
      :purchase_order_number,
      :started_at,
      :terminated_at,
      :terminated?,
      :active?,
      :terminated_at?,
      :date_diff_with_timezone,
      :calendar?,
      :anniversary?,
      :fees,
      to: :record

    def subscription_id
      return record.id if subscription?

      nil
    end

    def contract_id
      contract&.id
    end

    def currency
      return subscription.plan.amount_currency if subscription?

      contract.currency
    end

    def applicable_billing_entity
      return record.applicable_billing_entity if contract?

      record.billing_entity || record.customer.billing_entity
    end

    def plan_id
      return record.plan_id if subscription?

      nil
    end

    def subscription
      record if subscription?
    end

    def contract
      record if contract?
    end

    def subscription?
      return @is_subscription if defined?(@is_subscription)

      @is_subscription = record.is_a?(::Subscription)
    end

    def contract?
      return @is_contract if defined?(@is_contract)

      @is_contract = record.is_a?(::Contract)
    end

    def subscription_at
      return record.subscription_at if subscription?

      record.started_at
    end

    def invoice_subscriptions
      return record.invoice_subscriptions if subscription?

      []
    end

    def previous_subscription
      return record.previous_subscription if subscription?

      nil
    end

    def previous_subscription_id
      return record.previous_subscription_id if subscription?

      nil
    end

    def previous_subscription_id?
      previous_subscription_id.present?
    end

    def upgraded?
      return record.upgraded? if subscription?

      false
    end

    def downgraded?
      return record.downgraded? if subscription?

      false
    end

    private

    attr_reader :record
  end
end
