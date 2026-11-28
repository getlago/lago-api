# frozen_string_literal: true

module PaymentProviders
  class AdyenProvider < BaseProvider
    SUCCESS_REDIRECT_URL = "https://www.adyen.com/"

    WEBHOOKS_EVENTS = %w[AUTHORISATION CANCELLATION REFUND REFUND_FAILED CHARGEBACK].freeze
    IGNORED_WEBHOOK_EVENTS = %w[OFFER_CLOSED REPORT_AVAILABLE RECURRING_CONTRACT].freeze

    PROCESSING_STATUSES = %w[AuthorisedPending Received].freeze
    SUCCESS_STATUSES = %w[Authorised SentForSettle SettleScheduled Settled Refunded].freeze
    FAILED_STATUSES = %w[Cancelled CaptureFailed Error Expired Refused].freeze

    # Adyen's minor units differ from ISO 4217 (and Money) for these currencies: https://docs.adyen.com/development-resources/currency-codes
    ADYEN_DECIMALS_OVERRIDES = {"CLP" => 2, "HUF" => 2, "ISK" => 2, "CVE" => 0, "IDR" => 0}.freeze

    settings_accessors :live_prefix, :merchant_account
    secrets_accessors :api_key, :hmac_key

    validates :api_key, :merchant_account, presence: true
    validates :success_redirect_url, adyen_url: true, allow_nil: true, length: {maximum: 1024}

    def self.to_adyen_amount(amount_cents, currency)
      code = currency.to_s.upcase

      if amount_cents.nil? || !ADYEN_DECIMALS_OVERRIDES.key?(code)
        amount_cents
      else
        convert_minor_units(amount_cents, Money::Currency.new(code).exponent, ADYEN_DECIMALS_OVERRIDES[code])
      end
    end

    def self.from_adyen_amount(value, currency)
      code = currency.to_s.upcase

      if value.nil? || !ADYEN_DECIMALS_OVERRIDES.key?(code)
        value
      else
        convert_minor_units(value, ADYEN_DECIMALS_OVERRIDES[code], Money::Currency.new(code).exponent)
      end
    end

    def self.convert_minor_units(amount, from_exponent, to_exponent)
      shift = to_exponent - from_exponent

      if shift >= 0
        amount.to_i * 10**shift
      else
        (BigDecimal(amount.to_s) / 10**(-shift)).round(0, BigDecimal::ROUND_HALF_UP).to_i
      end
    end
    private_class_method :convert_minor_units

    def environment
      if Rails.env.production? && live_prefix.present?
        :live
      else
        :test
      end
    end

    def payment_type
      "adyen"
    end
  end
end

# == Schema Information
#
# Table name: payment_providers
# Database name: primary
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
