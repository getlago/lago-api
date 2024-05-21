# frozen_string_literal: true

class SalesOrder < ApplicationRecord
  self.table_name = 'invoices'

  has_many :integration_resources, as: :syncable
end
