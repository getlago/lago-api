# frozen_string_literal: true

class Customer
  class AppliedTax < ApplicationRecord
    self.table_name = "customers_taxes"

    include PaperTrailTraceable

    belongs_to :customer
    belongs_to :tax
  end
end

# == Schema Information
#
# Table name: customers_taxes
#
#  id          :uuid             not null, primary key
#  customer_id :uuid             not null
#  tax_id      :uuid             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_customers_taxes_on_customer_id             (customer_id)
#  index_customers_taxes_on_customer_id_and_tax_id  (customer_id,tax_id) UNIQUE
#  index_customers_taxes_on_tax_id                  (tax_id)
#
