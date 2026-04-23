# frozen_string_literal: true

module AuthenticableStaffUser
  extend ActiveSupport::Concern

  # Hard allowlist — ONLY these emails can access admin / staff-only GraphQL fields.
  # Map each email to a role:
  #   :admin — can toggle ANY premium integration
  #   :cs    — can toggle only the "safe" subset defined in STAFF_ROLE_PERMISSIONS
  #
  # Override at runtime with env var LAGO_STAFF_ALLOWED_EMAILS — same shape:
  #   "miguel@getlago.com:admin,support@getlago.com:cs"
  # If an entry has no role, it defaults to :cs.
  STAFF_ROLES = {
    "miguel@getlago.com" => :admin,
    "at@getlago.com" => :admin,
    "anh-tu@getlago.com" => :admin,
    "brian@getlago.com" => :admin,
    "raffi@getlago.com" => :admin,
    "jeremy@getlago.com" => :admin,
    "lovro@getlago.com" => :cs
  }.freeze

  STAFF_ROLE_PERMISSIONS = {
    admin: :all,
    cs: %w[
      remove_branding_watermark
      auto_dunning
      revenue_analytics
      analytics_dashboards
      from_email
      issue_receipts
      preview
    ].freeze
  }.freeze

  # Class-level (module-function) lookup so non-authenticated code paths (e.g. login) can
  # consult the allowlist without being forced to run through `ready?`.
  def self.role_for(email)
    return nil if email.blank?

    roles[email.to_s.downcase.strip]
  end

  def self.roles
    override = ENV["LAGO_STAFF_ALLOWED_EMAILS"].to_s
    if override.present?
      override.split(",").each_with_object({}) do |entry, acc|
        email, role = entry.split(":", 2).map { |v| v.to_s.strip }
        next if email.blank?

        acc[email.downcase] = (role.presence || "cs").to_sym
      end
    else
      STAFF_ROLES.transform_keys(&:downcase)
    end
  end

  private

  def ready?(**args)
    user = context[:current_user]
    raise unauthorized_error if user.blank?
    raise forbidden_staff_error if staff_role_for(user.email).blank?

    super
  end

  def staff_role_for(email)
    AuthenticableStaffUser.role_for(email)
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end

  def forbidden_staff_error
    GraphQL::ExecutionError.new("not_staff_member", extensions: {status: :forbidden, code: "not_staff_member"})
  end
end
