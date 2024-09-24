# frozen_string_literal: true

module PaymentProviders
  class CashfreeProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://cashfree.com/'
    API_VERSION = "2023-08-01"
    BASE_URL = (Rails.env.production? ? 'https://api.cashfree.com/pg/links' : 'https://sandbox.cashfree.com/pg/links')

    validates :client_id, presence: true
    validates :client_secret, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    secrets_accessors :client_id, :client_secret
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
