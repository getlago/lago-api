# frozen_string_literal: true

class AppliedWalletExpiration < ApplicationRecord
  belongs_to :organization
  belongs_to :invoice
  belongs_to :wallet

  validates :invoice_id, uniqueness: true
end

# == Schema Information
#
# Table name: applied_wallet_expirations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  invoice_id      :uuid             not null
#  organization_id :uuid             not null
#  wallet_id       :uuid             not null
#
# Indexes
#
#  index_applied_wallet_expirations_on_invoice_id       (invoice_id) UNIQUE
#  index_applied_wallet_expirations_on_organization_id  (organization_id)
#  index_applied_wallet_expirations_on_wallet_id        (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (wallet_id => wallets.id)
#
