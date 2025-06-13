# frozen_string_literal: true

module PaymentProviders
  class FlutterwaveProvider < BaseProvider
    FlutterwavePayment = Data.define(:id, :status, :metadata)

    SUCCESS_REDIRECT_URL = "https://www.flutterwave.com/ng"
    API_VERSION = "v3"
    BASE_URL = "https://api.flutterwave.com/v3"
    SANDBOX_URL = "https://ravesandboxapi.flutterwave.com/v3"

    PROCESSING_STATUSES = %w[pending].freeze
    SUCCESS_STATUSES = %w[successful].freeze
    FAILED_STATUSES = %w[failed cancelled].freeze

    validates :public_key, presence: true
    validates :secret_key, presence: true
    validates :encryption_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    secrets_accessors :public_key, :secret_key, :encryption_key
    settings_accessors :production, :webhook_secret

    before_create :generate_webhook_secret

    def payment_type
      "flutterwave"
    end

    def api_url
      production? ? BASE_URL : SANDBOX_URL
    end

    def production?
      ActiveModel::Type::Boolean.new.cast(production)
    end

    private

    def generate_webhook_secret
      self.webhook_secret = SecureRandom.hex(32) if webhook_secret.blank?
    end
  end
end
