# frozen_string_literal: true

class PaymentReceipt < ApplicationRecord
  belongs_to :payment
  belongs_to :organization
end

# == Schema Information
#
# Table name: payment_receipts
#
#  id              :uuid             not null, primary key
#  number          :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  payment_id      :uuid             not null
#
# Indexes
#
#  index_payment_receipts_on_organization_id  (organization_id)
#  index_payment_receipts_on_payment_id       (payment_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_id => payments.id)
#
