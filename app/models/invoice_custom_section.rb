# frozen_string_literal: true

class InvoiceCustomSection < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
end
