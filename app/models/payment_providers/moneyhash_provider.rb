# frozen_string_literal: true

module PaymentProviders
  class MoneyhashProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://moneyhash.io/'

    validates :api_key, presence: true
    validates :flow_id, url: true, presence: true, length: {maximum: 20}

    secrets_accessors :api_key
    settings_accessors :flow_id

    def self.api_base_url
      if Rails.env.production?
        'https://web.moneyhash.io'
      else
        'https://staging-web.moneyhash.io'
      end
    end

    def webhook_end_point
      URI.join(
        ENV['LAGO_API_URL'],
        "webhooks/moneyhash/#{organization_id}?code=#{URI.encode_www_form_component(code)}"
      )
    end

    def environment
      if Rails.env.production? && live_prefix.present?
        :live
      else
        :test
      end
    end
  end
end

# == Schema Information
#
# Table name: payment_providers
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
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
#  index_payment_providers_on_code_and_organization_id  (code,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_payment_providers_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
