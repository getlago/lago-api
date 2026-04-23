# frozen_string_literal: true

class AdminUser < ApplicationRecord
  ROLES = {
    admin: "admin",
    cs: "cs"
  }.freeze

  has_secure_password

  enum :role, ROLES, validate: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: {case_sensitive: false}, email: true
  validates :password, length: {minimum: 12}, if: -> { password.present? }

  def allowed_integrations
    allowed = Admin::PremiumIntegrations::ToggleService::ROLE_ALLOWED_INTEGRATIONS[role.to_sym]
    (allowed == :all) ? Organization::PREMIUM_INTEGRATIONS : Array(allowed)
  end
end
