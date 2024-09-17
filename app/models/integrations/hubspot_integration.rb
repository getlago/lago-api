# frozen_string_literal: true

module Integrations
  class HubspotIntegration < BaseIntegration
    validates :connection_id, :private_app_token, :default_targeted_object, presence: true

    settings_accessors :default_targeted_object, :sync_subscriptions, :sync_invoices
    secrets_accessors :connection_id, :private_app_token

    TARGETED_OBJECTS = %w[Companies Contacts]
  end
end

# == Schema Information
#
# Table name: integrations
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_integrations_on_code_and_organization_id  (code,organization_id) UNIQUE
#  index_integrations_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
