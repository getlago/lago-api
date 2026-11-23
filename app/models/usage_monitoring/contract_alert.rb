# frozen_string_literal: true

module UsageMonitoring
  class ContractAlert < ApplicationRecord
    include Discard::Model
    include ThresholdEvaluation

    self.discard_column = :deleted_at
    self.inheritance_column = :alert_type

    STI_MAPPING = {
      "usage_amount" => "UsageMonitoring::ContractUsageAmountAlert",
      "usage_units" => "UsageMonitoring::ContractUsageUnitsAlert"
    }.freeze

    default_scope -> { kept }

    belongs_to :organization
    belongs_to :product, -> { with_discarded }, optional: true
    belongs_to :product_filter, -> { with_discarded }, optional: true

    has_many :thresholds,
      class_name: "UsageMonitoring::ContractAlertThreshold",
      dependent: :delete_all,
      inverse_of: :alert

    has_many :triggered_alerts,
      -> { triggered },
      class_name: "UsageMonitoring::ContractTriggeredAlert"

    has_many :all_triggered_alerts,
      class_name: "UsageMonitoring::ContractTriggeredAlert",
      inverse_of: :alert

    enum :direction, Alert::DIRECTIONS, validate: true

    validates :alert_type, presence: true, inclusion: {in: STI_MAPPING.keys}
    validates :code, presence: true
    validates :contract_external_id, presence: true
    validates :product, presence: true, if: :need_product?
    validate :validate_product_filter_belongs_to_product
    validate :validate_with_product_filters

    def self.find_sti_class(type_name)
      STI_MAPPING.fetch(type_name).constantize
    end

    def self.sti_name
      STI_MAPPING.invert.fetch(name)
    end

    private

    # Units of different products do not add up, and a filter only narrows its own product
    def need_product?
      alert_type == "usage_units" || product_filter.present?
    end

    def validate_product_filter_belongs_to_product
      return if product_filter.nil? || product.nil?

      errors.add(:product_filter, :invalid) if product_filter.product_id != product.id
    end

    # The flag only widens a product scope to the product's filter cards
    def validate_with_product_filters
      errors.add(:with_product_filters, :invalid) if with_product_filters && (product.nil? || product_filter.present?)
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_contract_alerts
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  alert_type           :enum             not null
#  code                 :string           not null
#  deleted_at           :datetime
#  direction            :enum             default("increasing"), not null
#  last_processed_at    :datetime
#  name                 :string
#  previous_value       :decimal(30, 5)   default(0.0), not null
#  previous_windows     :jsonb            not null
#  with_product_filters :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  contract_external_id :string           not null
#  organization_id      :uuid             not null
#  product_filter_id    :uuid
#  product_id           :uuid
#
# Indexes
#
#  idx_contract_alerts_code_unique   (organization_id,contract_external_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  idx_contract_alerts_scope_unique  (organization_id,contract_external_id,alert_type,product_id,product_filter_id) UNIQUE NULLS NOT DISTINCT WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#  fk_rails_...  (product_id => products.id)
#
