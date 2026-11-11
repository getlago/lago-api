# frozen_string_literal: true

module CreditAllocationRule
  extend ActiveSupport::Concern

  TRIGGERS = {
    billing_cycle: "billing_cycle",
    ongoing_balance: "ongoing_balance"
  }.freeze

  included do
    include PaperTrailTraceable
    include Discard::Model
    include CatalogCodeFormat

    self.discard_column = :deleted_at

    belongs_to :organization
    belongs_to :product, -> { with_discarded }, optional: true
    belongs_to :product_filter, -> { with_discarded }, optional: true

    enum :trigger, TRIGGERS, validate: true

    validates :code, presence: true
    validates :credit_amount_cents, numericality: {only_integer: true, greater_than: 0}
    validates :priority, inclusion: {in: 1..CatalogWalletSettings::LOWEST_PRIORITY}
    validates :billing_cycles, numericality: {only_integer: true, greater_than: 0}, allow_nil: true
    validates :threshold_amount_cents, :purchase_amount_cents,
      numericality: {only_integer: true, greater_than_or_equal_to: 0},
      allow_nil: true
    validates_with ParentPresenceValidator,
      parents: %i[product product_filter],
      error: :exactly_one_source_required,
      if: :billing_cycle?

    default_scope -> { kept }
  end
end
