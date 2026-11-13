# frozen_string_literal: true

module CatalogWalletSettings
  extend ActiveSupport::Concern

  TAX_APPLICATIONS = {
    tax_on_consumption: "tax_on_consumption",
    tax_on_purchase: "tax_on_purchase"
  }.freeze

  LOWEST_PRIORITY = 50

  included do
    include PaperTrailTraceable
    include Currencies
    include Discard::Model
    include CatalogCodeFormat

    self.discard_column = :deleted_at

    belongs_to :organization

    has_many :selectors, class_name: "CatalogWalletSelector"
    has_many :applied_taxes, class_name: "CatalogWalletAppliedTax"
    has_many :taxes, through: :applied_taxes
    has_one :metadata, class_name: "Metadata::ItemMetadata", as: :owner, dependent: :destroy

    enum :tax_application, TAX_APPLICATIONS, validate: true

    validates :code, presence: true
    validates :currency, inclusion: {in: currency_list}
    validates :priority,
      numericality: {only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: LOWEST_PRIORITY}
    validates :top_up_min_amount_cents, :top_up_max_amount_cents,
      numericality: {only_integer: true, greater_than_or_equal_to: 0},
      allow_nil: true
    validates :top_up_max_amount_cents,
      numericality: {greater_than_or_equal_to: :top_up_min_amount_cents},
      if: -> { top_up_min_amount_cents && top_up_max_amount_cents }

    default_scope -> { kept }
  end
end
