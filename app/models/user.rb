# frozen_string_literal: true

class User < ApplicationRecord
  include PaperTrailTraceable

  has_secure_password

  has_many :password_resets
  has_many :user_devices

  has_many :memberships
  has_many :organizations, through: :memberships, class_name: "Organization"

  has_many :active_memberships, -> { where(status: "active") }, class_name: "Membership"
  has_many :active_organizations, through: :active_memberships, source: :organization

  has_many :quote_owners, dependent: :destroy
  has_many :quotes, through: :quote_owners

  validates :email, presence: true
  # A confirmed self-serve signup copies the bcrypt digest computed at Step 1: the password itself is never kept.
  validates :password, presence: true, unless: :created_from_password_digest?

  normalizes :email, with: ->(email) { EmailSanitizer.call(email) }

  # One query whether or not the email exists, so login timing does not reveal accounts. An exact match wins, then
  # the oldest case-insensitive one, as legacy rows can differ only by case.
  def self.lookup_by_email(email)
    normalized = normalize_value_for(:email, email.to_s).to_s

    where("LOWER(email) IN (?)", [normalized.downcase, email.to_s.downcase].uniq)
      .order(Arel.sql(sanitize_sql_array(["email = ? DESC", normalized])), :created_at)
      .first
  end

  def can?(permission, organization:)
    memberships.find { |m| m.organization_id == organization.id }&.can?(permission)
  end

  def login_method_allowed?(login_method)
    active_organizations.pluck(:authentication_methods).flatten.uniq.include?(login_method)
  end

  # Only a user created by a self-serve signup (confirmed email link or company Google account) who never belonged
  # to an organization may log in without one: a removed member regains access only through an invitation.
  def needs_organization?
    Lago::SelfServe.enabled? && self_serve_verified_at? && !cs_admin? && memberships.empty?
  end

  private

  def created_from_password_digest?
    new_record? && password.nil? && password_digest.present?
  end
end

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                     :uuid             not null, primary key
#  cs_admin               :boolean          default(FALSE), not null
#  email                  :string
#  password_digest        :string
#  self_serve_verified_at :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_email        (email)
#  index_users_on_lower_email  (lower((email)::text))
#
