# frozen_string_literal: true

module Subscriptions
  # NOTE: Splits the subscriptions of one customer into the groups that can share an invoice.
  #       Periodic billing and plan upgrades/downgrades must group the same way.
  class InvoiceGroupingService < BaseService
    Result = BaseResult[:subscription_groups]

    def initialize(subscriptions:)
      @subscriptions = subscriptions

      super
    end

    def call
      subscription_groups = group_by_payment_method(subscriptions)
      subscription_groups = group_by_currency(subscription_groups)
      subscription_groups = group_by_billing_entity(subscription_groups)
      subscription_groups = split_consolidation_opted_out(subscription_groups)
      subscription_groups = group_by_purchase_order_number(subscription_groups)
      subscription_groups = group_by_resolved_payment_term(subscription_groups)

      result.subscription_groups = subscription_groups
      result
    end

    private

    attr_reader :subscriptions

    def group_by_currency(subscription_groups)
      subscription_groups.flat_map do |subscriptions|
        subscriptions.group_by { |sub| sub.plan.amount_currency }.values
      end
    end

    # NOTE: A subscription with `consolidate_invoice = false` is never billed with other subscriptions,
    #       regardless of the other grouping criteria. Rows sharing its external_id (the terminated and
    #       the new subscription of a plan change) are the same subscription, so they stay together.
    def split_consolidation_opted_out(subscription_groups)
      subscription_groups.flat_map do |subscriptions|
        opted_out, consolidated = subscriptions.partition { |sub| !sub.consolidate_invoice }
        groups = opted_out.group_by(&:external_id).values
        groups << consolidated if consolidated.any?
        groups
      end
    end

    def group_by_billing_entity(subscription_groups)
      subscription_groups.flat_map do |subscriptions|
        subscriptions.group_by { |sub| sub.billing_entity_id || sub.customer.billing_entity_id }.values
      end
    end

    def group_by_purchase_order_number(subscription_groups)
      subscription_groups.flat_map do |subscriptions|
        subscriptions.group_by(&:purchase_order_number).values
      end
    end

    # NOTE: Subscriptions resolving to different payment terms cannot share an invoice.
    #       BillSubscriptionJob re-resolves and splits mixed groups itself, covering term
    #       changes racing with this grouping.
    def group_by_resolved_payment_term(subscription_groups)
      subscription_groups.flat_map do |subscriptions|
        groups = subscriptions.group_by do |subscription|
          PaymentTerms::ResolveService.call!(customer: subscription.customer).payment_term.grouping_key
        end.values

        if groups.many?
          Rails.logger.info(
            "InvoiceGroupingService - Customer #{subscriptions.first.customer_id} split into #{groups.size} payment term groups"
          )
        end

        groups
      end
    end

    # NOTE: Returns array of subscription groups
    #       - Groups subscriptions by their EFFECTIVE payment method (resolved, not raw)
    #       - If payment_method_id is nil, resolves to customer's default payment method
    #       - If all subscriptions resolve to the same payment method, returns single group
    #
    # Examples (assuming customer default is pm_1):
    #   - [nil, provider] + [nil, provider]   → single group (both resolve to pm_1)
    #   - [nil, provider] + [nil, manual]     → two groups (different type)
    #   - [pm_1, provider] + [nil, provider]  → single group (both resolve to pm_1)
    #   - [pm_1, provider] + [pm_2, provider] → two groups (different resolved id)
    def group_by_payment_method(subscriptions)
      return [subscriptions] if subscriptions.size <= 1

      customer = subscriptions.first.customer
      default_payment_method = customer.default_payment_method

      resolved_keys = subscriptions.map { |s| resolve_payment_method_key(s, default_payment_method) }.uniq

      if resolved_keys.size == 1
        return [subscriptions]
      end

      subscriptions.group_by { |s| resolve_payment_method_key(s, default_payment_method) }.values
    end

    # NOTE: Returns the effective payment method key for grouping
    #       - If subscription has explicit payment_method_id, use it
    #       - If nil, inherit from customer's default payment method
    def resolve_payment_method_key(subscription, default_payment_method)
      if subscription.payment_method_id.present?
        [subscription.payment_method_id, subscription.payment_method_type]
      elsif subscription.payment_method_type == "manual"
        [nil, "manual"]
      elsif default_payment_method.present?
        [default_payment_method.id, "provider"]
      else
        [nil, subscription.payment_method_type]
      end
    end
  end
end
