# frozen_string_literal: true

# Resolves the effective connection of each category (payment / tax / accounting / crm) for a
# billing object, cascading an explicit per-object override to the customer default:
#
#   * an override row (billing_object_connections) with behavior "specific" pins its connection
#   * an override row with behavior "skip" resolves to nil (no connection for that category)
#   * no override row means "inherit": fall back to the customer's default connection
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
    overrides = billing_object_connections.index_by(&:category)

    CATEGORIES.each_value.map do |category|
      override = overrides[category]

      connection = if override.nil?
        customer_default_connection(category)
      elsif override.skip?
        nil
      else
        override_connection(override, category)
      end

      Routing.new(
        category: category,
        behavior: override&.behavior || INHERIT_BEHAVIOR,
        code: connection&.code
      )
    end
  end

  private

  def effective_connection(category)
    override = billing_object_connections.find_by(category:)

    if override
      return nil if override.skip?

      return override_connection(override, category)
    end

    customer_default_connection(category)
  end

  def override_connection(override, category)
    if category == CATEGORIES[:payment]
      override.payment_provider_customer
    else
      override.integration_customer
    end
  end

  def customer_default_connection(category)
    return unless customer

    if category == CATEGORIES[:payment]
      customer.payment_provider_customers.detect(&:is_default?)
    else
      customer.integration_customers.detect { it.category == category && it.is_default? }
    end
  end
end
