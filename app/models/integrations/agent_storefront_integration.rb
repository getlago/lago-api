# frozen_string_literal: true

module Integrations
  class AgentStorefrontIntegration < BaseIntegration
    validates :code, :payment_provider_code, :scope, presence: true
    validate :https_urls
    validate :stripe_provider_exists

    settings_accessors :payment_provider_code, :resource_endpoint, :resource_instructions, :scope

    def stripe_provider
      organization&.stripe_payment_providers&.find_by(code: payment_provider_code)
    end

    private

    def https_urls
      %i[resource_endpoint resource_instructions].each do |attribute|
        value = public_send(attribute)
        next if value.blank?

        uri = URI.parse(value)
        errors.add(attribute, :url_invalid) unless uri.is_a?(URI::HTTPS) && uri.host.present?
      rescue URI::InvalidURIError
        errors.add(attribute, :url_invalid)
      end
    end

    def stripe_provider_exists
      return if payment_provider_code.blank?

      errors.add(:payment_provider_code, "payment_provider_not_found") unless stripe_provider
    end
  end
end

# == Schema Information
#
# Table name: integrations
# Database name: primary
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
