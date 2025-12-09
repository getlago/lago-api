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
