# frozen_string_literal: true

module PaymentProviders
  class PaystackProvider < BaseProvider
    PaystackPayment = Data.define(:id, :status, :metadata, :authorization, :reference, :amount, :currency, :gateway_response)

    SUCCESS_REDIRECT_URL = "https://paystack.com"
    API_URL = "https://api.paystack.co"

    PROCESSING_STATUSES = %w[pending processing ongoing queued].freeze
    SUCCESS_STATUSES = %w[success].freeze
    FAILED_STATUSES = %w[failed abandoned reversed].freeze
    SUPPORTED_CURRENCIES = %w[NGN GHS ZAR KES USD XOF].freeze

    PAYABLE_PAYMENT_STATUS_MAP = {
      "pending" => "pending",
      "processing" => "pending",
      "ongoing" => "pending",
      "queued" => "pending",
      "success" => "succeeded",
      "failed" => "failed",
      "abandoned" => "failed",
      "reversed" => "failed"
    }.freeze

    validates :secret_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    secrets_accessors :secret_key

    def payment_type
      "paystack"
    end

    def api_url
      API_URL
    end

    def webhook_end_point
      URI.join(
        ENV["LAGO_API_URL"],
        "webhooks/paystack/#{organization_id}?code=#{URI.encode_www_form_component(code)}"
      )
    end

    def payable_payment_status(paystack_status)
      PAYABLE_PAYMENT_STATUS_MAP[paystack_status.to_s]
    end

    def self.supported_currency?(currency)
      SUPPORTED_CURRENCIES.include?(currency.to_s.upcase)
    end
  end
end
