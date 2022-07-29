class InvoiceSubscription < ApplicationRecord
  belongs_to :invoice
  belongs_to :subscription
end