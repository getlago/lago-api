# frozen_string_literal: true

# Resolves the effective connection of each category (payment / tax / accounting / crm) for a
# billing object, cascading an explicit per-object override to the customer default:
#
#   * an override row (billing_object_connections) with behavior "specific" pins its connection
#   * an override row with behavior "skip" resolves to nil (no connection for that category)
#   * no override row means "inherit": fall back to fallback_record connection if defined,
#     otherwise use the customer's default connection.
#
# For a single-connection customer with no overrides this returns that connection, so behaviour
# is unchanged.
module ConnectionResolvable
  extend ActiveSupport::Concern

  CATEGORIES = BillingObjectConnection::CATEGORIES

  # Read-side only: the absence of an override row is reported as "inherit". The column itself
  # only ever holds "specific" or "skip".
  INHERIT_BEHAVIOR = "inherit"
  ROUTING_BEHAVIORS = (BillingObjectConnection::BEHAVIORS.values + [INHERIT_BEHAVIOR]).freeze

  Routing = Data.define(:category, :behavior, :code)

  def effective_payment_connection
    effective_connection(CATEGORIES[:payment])
  end

  def effective_tax_connection
    effective_connection(CATEGORIES[:tax])
  end

  def effective_accounting_connection
    effective_connection(CATEGORIES[:accounting])
  end

  def effective_crm_connection
    effective_connection(CATEGORIES[:crm])
  end

  # The routing of every category, for read surfaces: the stored behaviour ("inherit" when no
  # override row exists) alongside the code of the connection actually in effect. Overrides are
  # loaded once rather than per category, so `includes(:billing_object_connections)` on a
  # collection keeps this to one query.
  def connection_routing
    CATEGORIES.each_value.map do |category|
      override = billing_object_connection(category, cache: true)

      behavior = routing_behavior(override, category)
      connection = routing_connection(override, category)

      Routing.new(category:, behavior:, code: connection&.code)
    end
  end

  def effective_connection(category, cache: false)
    override = billing_object_connection(category, cache:)

    if override
      return nil if override.skip?
      return override_connection(override, category, cache:)
    end

    fallback_connection(category, cache:)
  end

  def fallback_record
    nil
  end

  private

  def billing_object_connection(category, cache:)
    if cache
      billing_object_connections.detect { it.category == category.to_s }
    else
      billing_object_connections.find_by(category:)
    end
  end

  # PaymentProviders::DestroyService soft-deletes provider customers with update_all
  # and leaves their billing_object_connections, which results in payment_provider_customer
  # resolving to nil here. In this case we return fallback_connection.
  def override_connection(override, category, cache:)
    if category == CATEGORIES[:payment]
      override.payment_provider_customer || fallback_connection(category, cache:)
    else
      override.integration_customer
    end
  end

  def fallback_connection(category, cache:)
    if fallback_record
      fallback_record.effective_connection(category, cache:)
    else
      customer_default_connection(category)
    end
  end

  def customer_default_connection(category)
    return unless customer

    if category == CATEGORIES[:payment]
      default_among(customer.payment_provider_customers.to_a)
    else
      default_among(customer.integration_customers.select { it.category == category })
    end
  end

  def default_among(connections)
    return connections.first if connections.one?

    connections.detect(&:is_default?)
  end

  def routing_behavior(override, category)
    if override.nil?
      INHERIT_BEHAVIOR
    elsif soft_deleted_payment_provider_customer?(override, category)
      INHERIT_BEHAVIOR
    else
      override.behavior
    end
  end

  # If PaymentProviderCustomer is soft-deleted but the billing_object_connection
  # is still there, we return "inherit" instead of "specific".
  def soft_deleted_payment_provider_customer?(override, category)
    override.specific? && category == CATEGORIES[:payment] && override.payment_provider_customer.nil?
  end

  def routing_connection(override, category)
    if override.nil?
      fallback_connection(category, cache: true)
    elsif override.skip?
      nil
    else
      override_connection(override, category, cache: true)
    end
  end
end
