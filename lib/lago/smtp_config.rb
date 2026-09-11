# frozen_string_literal: true

require "active_model"
require "active_support/core_ext/object/blank"

module Lago
  module SmtpConfig
    DEFAULT_AUTHENTICATION = "login"

    DISABLED_AUTHENTICATIONS = ["none", "disabled"].freeze

    # Methods net-smtp can actually perform. Any other value raises
    # `ArgumentError` when the first email is delivered.
    AUTHENTICATION_METHODS = %w[login plain cram_md5 xoauth2].freeze

    class << self
      def authentication
        value = ENV.fetch("LAGO_SMTP_AUTHENTICATION", DEFAULT_AUTHENTICATION).to_s.strip.presence ||
          DEFAULT_AUTHENTICATION

        if DISABLED_AUTHENTICATIONS.include?(value.downcase)
          nil
        else
          value
        end
      end

      def authenticated?
        !authentication.nil?
      end

      def user_name
        authenticated? ? ENV["LAGO_SMTP_USERNAME"] : nil
      end

      def password
        authenticated? ? ENV["LAGO_SMTP_PASSWORD"] : nil
      end

      def authentication_supported?
        AUTHENTICATION_METHODS.include?(authentication.to_s.downcase)
      end

      def starttls_auto?
        ActiveModel::Type::Boolean.new.cast(
          ENV.fetch("LAGO_SMTP_ENABLE_STARTTLS_AUTO", true).presence || true
        )
      end
    end
  end
end
