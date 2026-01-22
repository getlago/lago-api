# frozen_string_literal: true

class PendingViesCheck < ApplicationRecord
  belongs_to :organization
  belongs_to :billing_entity
  belongs_to :customer
end

# == Schema Information
#
# Table name: pending_vies_checks
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  attempts_count            :integer          default(0), not null
#  last_attempt_at           :datetime
#  last_error_message        :text
#  last_error_type           :string
#  tax_identification_number :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  billing_entity_id         :uuid             not null
#  customer_id               :uuid             not null
#  organization_id           :uuid             not null
#
# Indexes
#
#  index_pending_vies_checks_on_billing_entity_id  (billing_entity_id)
#  index_pending_vies_checks_on_customer_id        (customer_id) UNIQUE
#  index_pending_vies_checks_on_organization_id    (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#
