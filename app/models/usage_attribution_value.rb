# frozen_string_literal: true

class UsageAttributionValue < ApplicationRecord
  include Discard::Model

  self.discard_column = :deleted_at

  MAX_PER_CUSTOMER_AND_TYPE = 100_000
  LIMIT_REACHED_CACHE_TTL = 1.hour

  belongs_to :organization
  belongs_to :usage_attribution_type, -> { with_discarded }
  belongs_to :customer, -> { with_discarded }
  belongs_to :parent, -> { with_discarded }, class_name: "UsageAttributionValue", optional: true
  has_many :children, class_name: "UsageAttributionValue", foreign_key: :parent_id, inverse_of: :parent

  validates :value, presence: true, length: {maximum: 255}, uniqueness: {scope: %i[customer_id usage_attribution_type_id]}

  default_scope -> { kept }

  def self.remaining_capacity(customer_id:, usage_attribution_type_id:)
    cache_key = "usage_attribution_values/limit_reached/#{customer_id}/#{usage_attribution_type_id}"
    return 0 if Rails.cache.read(cache_key)

    remaining = MAX_PER_CUSTOMER_AND_TYPE - where(customer_id:, usage_attribution_type_id:).limit(MAX_PER_CUSTOMER_AND_TYPE).count

    if remaining.zero?
      Rails.cache.write(cache_key, true, expires_in: LIMIT_REACHED_CACHE_TTL)
      Rails.logger.warn("Usage attribution values limit reached: customer #{customer_id}, usage attribution type #{usage_attribution_type_id}")
    end

    remaining
  end

  def self.limit_reached?(customer_id:, usage_attribution_type_id:)
    remaining_capacity(customer_id:, usage_attribution_type_id:).zero?
  end
end

# == Schema Information
#
# Table name: usage_attribution_values
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  deleted_at                :datetime
#  last_seen_at              :datetime
#  value                     :string           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  customer_id               :uuid             not null
#  organization_id           :uuid             not null
#  parent_id                 :uuid
#  usage_attribution_type_id :uuid             not null
#
# Indexes
#
#  index_usage_attribution_values_on_customer_id                   (customer_id)
#  index_usage_attribution_values_on_customer_id_and_last_seen_at  (customer_id,last_seen_at)
#  index_usage_attribution_values_on_customer_type_and_value       (customer_id,usage_attribution_type_id,value) UNIQUE
#  index_usage_attribution_values_on_organization_id               (organization_id)
#  index_usage_attribution_values_on_parent_id                     (parent_id)
#  index_usage_attribution_values_on_usage_attribution_type_id     (usage_attribution_type_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (parent_id => usage_attribution_values.id)
#  fk_rails_...  (usage_attribution_type_id => usage_attribution_types.id)
#
