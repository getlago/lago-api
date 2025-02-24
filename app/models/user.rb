# frozen_string_literal: true

class User < ApplicationRecord
  include PaperTrailTraceable
  has_secure_password

  LOGIN_METHODS = [
    :email,
    :google,
    :okta
  ].freeze

  enum :last_login_method, LOGIN_METHODS

  has_many :password_resets

  has_many :memberships
  has_many :organizations, through: :memberships, class_name: "Organization"

  has_many :billable_metrics, through: :organizations
  has_many :customers, through: :organizations
  has_many :plans, through: :organizations
  has_many :coupons, through: :organizations
  has_many :add_ons, through: :organizations
  has_many :credit_notes, through: :organizations
  has_many :wallets, through: :organizations
  has_many :subscriptions, through: :customers

  validates :email, presence: true
  validates :password, presence: true, on: :create

  def can?(permission, organization:)
    memberships.find { |m| m.organization_id == organization.id }&.can?(permission)
  end

  def touch_last_login!(method)
    update!(last_login_method: method, last_login_at: Time.current)
  end
end

# == Schema Information
#
# Table name: users
#
#  id                :uuid             not null, primary key
#  email             :string
#  last_login_at     :datetime
#  last_login_method :integer
#  password_digest   :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
