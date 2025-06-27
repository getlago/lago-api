# frozen_string_literal: true

module Organizations::Auths
  extend ActiveSupport::Concern

  FREE_AUTHS = %w[password google_oauth]
  PREMIUM_AUTHS = %w[okta]
  AUTH_METHODS = FREE_AUTHS + PREMIUM_AUTHS

  included do
    validates :enabled_auths, length: {minimum: 1}
    validates :enabled_auths, inclusion: {in: AUTH_METHODS}

    FREE_AUTHS.each do |method|
      define_method("#{method}_enabled_auth?") do
        enabled_auths.include?(method)
      end

      define_method("enable_#{method}_auth!") do
        return true if send("#{method}_enabled_auth?")

        enabled_auths << method
        save!
      end
    end

    PREMIUM_AUTHS.each do |method|
      define_method("#{method}_enabled_auth?") do
        License.premium? && enabled_auths.include?(method)
      end

      define_method("enable_#{method}_auth!") do
        return false unless License.premium?
        return true if send("#{method}_enabled_auth?")

        enabled_auths << method
        save!
      end
    end

    AUTH_METHODS.each do |method|
      define_method("disable_#{method}_auth!") do
        return false unless send("#{method}_enabled_auth?")

        enabled_auths.delete(method)
        save!
      end
    end
  end
end
