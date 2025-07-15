# frozen_string_literal: true

module Chargable
  extend ActiveSupport::Concern

  included do
    include Discard::Model
    self.discard_column = :deleted_at

    belongs_to :organization
    belongs_to :plan, -> { with_discarded }, touch: true
    belongs_to :parent, class_name: name, optional: true

    has_many :children, class_name: name, foreign_key: :parent_id, dependent: :nullify
    has_many :fees

    # Common validations
    validates :charge_model, presence: true
    validates :pay_in_advance, inclusion: { in: [true, false] }
    validates :prorated, inclusion: { in: [true, false] }
    validates :properties, presence: true

    # Common scopes
    default_scope -> { kept }
    scope :pay_in_advance, -> { where(pay_in_advance: true) }
  end

  def equal_properties?(other_charge)
    charge_model == other_charge.charge_model && properties == other_charge.properties
  end
end 