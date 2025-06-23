# frozen_string_literal: true

class RunCustomerCurrencyTask < ActiveRecord::Migration[7.0]
  def up
    update_query = <<~SQL
      WITH customer_currency AS (
        SELECT customers.id AS customer_id, plans.amount_currency AS currency
        FROM customers
          INNER JOIN subscriptions ON customers.id = subscriptions.customer_id
          INNER JOIN plans ON subscriptions.plan_id = plans.id
        WHERE currency IS NULL
        GROUP BY customers.id, plans.amount_currency
        HAVING COUNT(DISTINCT(plans.amount_currency)) = 1
      )

      UPDATE customers
      SET currency = customer_currency.currency
      FROM customer_currency
      WHERE customers.id = customer_currency.customer_id
    SQL

    safety_assured { execute(update_query) }
  end
end
