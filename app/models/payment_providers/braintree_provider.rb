# frozen_string_literal: true

module PaymentProviders
  class BraintreeProvider < BaseProvider
    PROCESSING_STATUTES = %w[submitted_for_settlement settlement_pending authorizing settling].freeze
    SUCCESS_STATUSES = %w[settled authorized].freeze
    FAILED_STATUSES = %w[authorization_expired processor_declined gateway_rejected failed voided settlement_declined].freeze

    WEBHOOK_EVENTS = %w[
      transaction_settled
      transaction_settlement_declined
      transaction_disbursed
      paypal_account_revoked
    ].freeze

    validates :merchant_id, presence: true
    validates :public_key, presence: true
    validates :private_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true

    secrets_accessors :public_key, :private_key
    settings_accessors :merchant_id, :supports_3ds

    def environment
      Rails.env.production? ? :production : :sandbox
    end

    def payment_type
      "braintree"
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
