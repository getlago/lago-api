# frozen_string_literal: true

module PaymentProviders
  class GocardlessProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://gocardless.com/'

    validates :access_token, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    secrets_accessors :access_token

    def self.auth_site
      if Rails.env.production?
        'https://connect.gocardless.com'
      else
        'https://connect-sandbox.gocardless.com'
      end
    end

    def environment
      if Rails.env.production?
        :live
      else
        :sandbox
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
#  index_payment_providers_on_code_and_organization_id  (code,organization_id) UNIQUE
#  index_payment_providers_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
