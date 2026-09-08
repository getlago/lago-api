# frozen_string_literal: true

require "active_model"
require "active_support/core_ext/object/blank"

module Lago
  module SmtpConfig
    DISABLED_AUTHENTICATIONS = ["none", "disabled"].freeze

    # Methods net-smtp can actually perform. Any other value raises
    # `ArgumentError` when the first email is delivered.
    AUTHENTICATION_METHODS = %w[login plain cram_md5 xoauth2].freeze

    class << self
      def authentication
        value = ENV.fetch("LAGO_SMTP_AUTHENTICATION", "login").to_s.strip

        if value.blank? || DISABLED_AUTHENTICATIONS.include?(value.downcase)
          nil
        else
          value
        end
      end

      def authenticated?
        !authentication.nil?
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
