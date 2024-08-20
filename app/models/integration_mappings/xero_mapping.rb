# frozen_string_literal: true

module IntegrationMappings
  class XeroMapping < BaseMapping
  end
end

# == Schema Information
#
# Table name: integration_mappings
#
#  id             :uuid             not null, primary key
#  mappable_type  :string           not null
#  settings       :jsonb            not null
#  type           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  integration_id :uuid             not null
#  mappable_id    :uuid             not null
#
# Indexes
#
#  index_integration_mappings_on_integration_id  (integration_id)
#  index_integration_mappings_on_mappable        (mappable_type,mappable_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_id => integrations.id)
#
