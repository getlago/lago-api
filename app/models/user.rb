# frozen_string_literal: true

class User < ApplicationRecord
  include PaperTrailTraceable
  has_secure_password

  has_many :password_resets

  has_many :memberships
  has_many :organizations, through: :memberships, class_name: "Organization"

  has_many :active_memberships, -> { where(status: "active") }, class_name: "Membership"
  has_many :active_organizations, through: :active_memberships, source: :organization

  has_many :billable_metrics, through: :organizations
  has_many :customers, through: :organizations
  has_many :plans, through: :organizations
  has_many :coupons, through: :organizations
  has_many :add_ons, through: :organizations
  has_many :credit_notes, through: :organizations
  has_many :wallets, through: :organizations
  has_many :subscriptions, through: :organizations

  validates :email, presence: true
  validates :password, presence: true

  def can?(permission, organization:)
    memberships.find { |m| m.organization_id == organization.id }&.can?(permission)
  end
end

# == Schema Information
#
# Table name: users
#
#  id              :uuid             not null, primary key
#  email           :string
#  password_digest :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
