# frozen_string_literal: true

module Metadata
  class CustomerMetadata < ApplicationRecord
    COUNT_PER_CUSTOMER = 5

    belongs_to :customer

    validates :key, presence: true, uniqueness: {scope: :customer_id}, length: {maximum: 20}
    validates :value, presence: true, length: {maximum: 40}

    scope :displayable, -> { where(display_in_invoice: true) }
  end
end

# == Schema Information
#
# Table name: customer_metadata
#
#  id                 :uuid             not null, primary key
#  display_in_invoice :boolean          default(FALSE), not null
#  key                :string           not null
#  value              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  customer_id        :uuid             not null
#
# Indexes
#
#  index_customer_metadata_on_customer_id          (customer_id)
#  index_customer_metadata_on_customer_id_and_key  (customer_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
