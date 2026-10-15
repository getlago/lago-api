# frozen_string_literal: true

class Invoice
  module SearchTerms
    SQL = <<~SQL.squish.freeze
      concat_ws(' ', invoices.number, invoices.purchase_order_number,
        (SELECT concat_ws(' ', c.name, c.firstname, c.lastname, c.legal_name, c.external_id, c.email)
         FROM customers c WHERE c.id = invoices.customer_id))
    SQL
  end
end
