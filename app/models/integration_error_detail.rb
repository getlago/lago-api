# frozen_string_literal: true

class IntegrationErrorDetail < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :error_producer, polymorphic: true
  belongs_to :owner, polymorphic: true
end
