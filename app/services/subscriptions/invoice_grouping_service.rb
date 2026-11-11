# frozen_string_literal: true

module Subscriptions
  # NOTE: Splits the subscriptions of one customer into the groups that can share an invoice.
  #       Periodic billing and plan upgrades/downgrades must group the same way.
  class InvoiceGroupingService < BaseService
    Result = BaseResult[:subscription_groups]

    CONNECTION_ID_ATTRIBUTES = {
      payment: :payment_provider_customer_id,
      tax: :integration_customer_id,
      accounting: :integration_customer_id,
      crm: :integration_customer_id
    }.freeze

    CONNECTION_CATEGORIES = CONNECTION_ID_ATTRIBUTES.keys.freeze

    def initialize(subscriptions:)
      @subscriptions = subscriptions

      super
    end

    def call
      subscription_groups = group_by_payment_method(subscriptions)
      subscription_groups = group_by_currency(subscription_groups)
      subscription_groups = group_by_billing_entity(subscription_groups)
      subscription_groups = group_by_connections(subscription_groups) if multi_connection_enabled?
      subscription_groups = split_consolidation_opted_out(subscription_groups)
      subscription_groups = group_by_purchase_order_number(subscription_groups)

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

    def multi_connection_enabled?
      subscriptions.first&.organization&.feature_flag_enabled?(:multi_connection)
    end

    # NOTE: Subscriptions sharing an invoice must use the same payment, tax, accounting and CRM connections.
    #       A subscription without an override inherits the default connections of its customer.
    def group_by_connections(subscription_groups)
      subscription_groups.flat_map do |subscriptions|
        next [subscriptions] if subscriptions.size <= 1

        subscriptions.group_by { |sub| connection_key(sub) }.values
      end
    end

    def connection_key(subscription)
      CONNECTION_CATEGORIES.map { |category| effective_connection_id(subscription, category) }
    end

    def effective_connection_id(subscription, category)
      override = subscription.billing_object_connections.find { |c| c.category == category.to_s }

      if override.nil?
        default_connection_id(subscription, category)
      elsif override.specific?
        override.public_send(CONNECTION_ID_ATTRIBUTES.fetch(category))
      end
    end

    def default_connection_id(subscription, category)
      key = [subscription.customer_id, category]

      default_connection_ids.fetch(key) do
        default_connection_ids[key] = resolve_default_connection_id(subscription.customer, category)
      end
    end

    def default_connection_ids
      @default_connection_ids ||= {}
    end

    def resolve_default_connection_id(customer, category)
      connections = customer_connections(customer, category)

      if connections.one?
        connections.first.id
      else
        connections.find(&:is_default?)&.id
      end
    end

    def customer_connections(customer, category)
      if category == :payment
        customer.payment_provider_customers.to_a
      else
        types = IntegrationCustomers::BaseCustomer::CATEGORY_BY_TYPE.select { |_, c| c == category.to_s }.keys
        customer.integration_customers.where(type: types).to_a
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
