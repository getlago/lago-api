# frozen_string_literal: true

class RateCard::AppliedTax < ApplicationRecord
  self.table_name = "rate_cards_taxes"

  include PaperTrailTraceable

  belongs_to :rate_card
  belongs_to :tax
  belongs_to :organization
end

# == Schema Information
#
# Table name: rate_cards_taxes
# Database name: primary
#
#  id              :uuid             not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  rate_card_id    :uuid             not null
#  tax_id          :uuid             not null
#
# Indexes
#
#  index_rate_cards_taxes_on_organization_id          (organization_id)
#  index_rate_cards_taxes_on_rate_card_id             (rate_card_id)
#  index_rate_cards_taxes_on_rate_card_id_and_tax_id  (rate_card_id,tax_id) UNIQUE
#  index_rate_cards_taxes_on_tax_id                   (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#  fk_rails_...  (tax_id => taxes.id)
#
