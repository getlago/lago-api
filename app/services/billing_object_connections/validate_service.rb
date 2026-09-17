# frozen_string_literal: true

module BillingObjectConnections
  class ValidateService < BaseValidator
    CATEGORIES = BillingObjectConnection::CATEGORIES.values.freeze
    # "specific" is never sent: it is implied by supplying a code. "inherit" is params-only
    # and means "destroy the override row", since row absence is what ConnectionResolvable
    # reads as inheritance.
    BEHAVIORS = %w[inherit skip].freeze

    # Pure validator: it accumulates error codes and leaves surfacing them to the caller, because
    # the wallet create path merges them into an accumulating validator while the update and
    # recurring-rule paths fail the result directly.
    def valid?
      validate_connections if connections.present?

      !errors?
    end

    def error_codes
      errors[:connections] || []
    end

    private

    def connections
      args[:connections]
    end

    def validate_connections
      unless connections.is_a?(Hash)
        add_error(field: :connections, error_code: "invalid_connections")
        return
      end

      connections.each do |category, choice|
        validate_category(category)
        validate_choice(choice)
      end
    end

    def validate_category(category)
      return true if CATEGORIES.include?(category.to_s)

      add_error(field: :connections, error_code: "invalid_connection_category")
    end

    def validate_choice(choice)
      unless choice.is_a?(Hash)
        add_error(field: :connections, error_code: "invalid_connection_choice")
        return
      end

      code = choice[:code]
      behavior = choice[:behavior]

      if code.present? && behavior.present?
        return add_error(field: :connections, error_code: "invalid_connection_choice")
      end

      if code.blank? && behavior.blank?
        return add_error(field: :connections, error_code: "invalid_connection_choice")
      end

      return true if behavior.blank? || BEHAVIORS.include?(behavior.to_s)

      add_error(field: :connections, error_code: "invalid_connection_behavior")
    end
  end
end
