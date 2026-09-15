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
      customer.payment_connection
    else
      customer.integration_connection(category)
    end
  end
end
