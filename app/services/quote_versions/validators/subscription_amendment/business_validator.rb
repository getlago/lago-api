# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionAmendment
      # An amendment payload is a subscription_creation one with extra constraints, so currency,
      # dates, plan overrides, coupons and wallet credits are all inherited. Only what is specific
      # to restating one plan on a live subscription is added here.
      class BusinessValidator < SubscriptionCreation::BusinessValidator
        def valid?
          validate_single_plan
          validate_end_date_presence
          validate_target_subscription

          # Errors accumulate in a hash, so the inherited pass still reports everything at once.
          super
        end

        private

        # Refused at both scopes so a draft never accumulates a second plan: the quote pins a single
        # target subscription, and execution amends that one.
        def validate_single_plan
          return if plans.count <= 1

          add_error(field: :"billing_items.plans", error_code: "single_plan_expected")
        end

        # subscription_creation deliberately allows an open-ended deal. An amendment restates the
        # contract term instead, and its ending date is what the replacement subscription carries.
        def validate_end_date_presence
          return unless scope == :approve
          return if quote_version.end_date.present?
          return if plans.first&.dig("payload", "endDate").present?

          add_error(field: :end_date, error_code: "value_is_mandatory")
        end

        # The quote pins its target at creation, where Quote requires it for this order type and
        # Quotes::CreateService scopes it to the deal's organization and customer. Only the state
        # that can change afterwards is checked here.
        # A quoted plan cheaper than the one the target runs on is legitimate: execution routes the
        # change through Subscriptions::CreateService, which schedules a reduction for the next
        # billing day rather than applying it mid-period.
        def validate_target_subscription
          subscription = quote_version.quote.subscription
          return add_error(field: :subscription_id, error_code: "value_is_mandatory") if subscription.nil?
          return if subscription.active?

          add_error(field: :subscription_id, error_code: "subscription_not_active")
        end
      end
    end
  end
end
