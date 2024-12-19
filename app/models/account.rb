# frozen_string_literal: true

class Account < ApplicationRecord
  self.abstract_class = true

  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
  has_many :invoices
end
