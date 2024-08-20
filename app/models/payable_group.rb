# frozen_string_literal: true

class PayableGroup < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :customer, -> { with_discarded }

  has_many :invoices
  has_many :payments, as: :payable
  has_many :payment_requests, as: :payment_requestable

  PAYMENT_STATUS = %i[pending succeeded failed].freeze

  enum payment_status: PAYMENT_STATUS, _prefix: :payment
end

# == Schema Information
#
# Table name: payable_groups
#
#  id              :uuid             not null, primary key
#  payment_status  :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  customer_id     :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_payable_groups_on_customer_id      (customer_id)
#  index_payable_groups_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#
