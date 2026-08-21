# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionAmendment
      # An amendment payload is a subscription_creation one with extra constraints, so currency,
      # plan overrides, coupons and wallet credits are all inherited. Only what is specific to
      # restating one plan on a live subscription is added here, and the inherited plan date
      # validation is narrowed down to the ending date, the one an amendment carries over.
      class BusinessValidator < SubscriptionCreation::BusinessValidator
        def valid?
          validate_single_plan
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

        # The target subscription is already bound to an entity, and the plan change carries that
        # binding over. Re-pinning it here would move a running subscription to another entity's
        # invoice-numbering series mid-life, so an amendment cannot name one at all.
        def validate_billing_entity
          return if quote_version.billing_entity_id.blank?

          add_error(field: :billing_entity_id, error_code: "not_supported_for_order_type")
        end

        # An amendment restates the term of a subscription that is already running: its start is the
        # target's own anniversary date, which the plan change carries over, so a quoted start date
        # is a commercial term only and is not validated here.
        # An absent ending date leaves the target's own in place, see the plan change services. The
        # start date being out of the picture, there is no range left to compare: the ending date
        # only has to be after the target's anniversary date, which its futureness already implies
        # since the target must be running.
        def validate_plan_dates(plan_item, index)
          end_date = plan_item.dig("payload", "endDate")
          return unless validate_plan_date(end_date, plan_field(index, "payload.endDate"))

          validate_future_end_date(end_date, plan_field(index, "payload.endDate"))
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
