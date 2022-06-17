# frozen_string_literal: true

class Payment < ApplicationRecord
  belongs_to :invoice
  belongs_to :payment_provider, optional: true
  belongs_to :payment_provider_customer
end
