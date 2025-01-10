class Partner < ApplicationRecord
  belongs_to :organization

  has_many :issued_invoices, class_name: "Invoice", as: :issuer
end

# == Schema Information
#
# Table name: partners
#
#  id              :uuid             not null, primary key
#  name            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_partners_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
