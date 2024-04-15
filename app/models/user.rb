# frozen_string_literal: true

class User < ApplicationRecord
  include PaperTrailTraceable
  include OtpAuthenticatable
  has_secure_password

  has_many :password_resets

  has_many :memberships
  has_many :organizations, through: :memberships, class_name: 'Organization'

  has_many :billable_metrics, through: :organizations
  has_many :customers, through: :organizations
  has_many :plans, through: :organizations
  has_many :coupons, through: :organizations
  has_many :add_ons, through: :organizations
  has_many :credit_notes, through: :organizations
  has_many :wallets, through: :organizations
  has_many :subscriptions, through: :customers

  validates :email, presence: true
  validates :password, presence: true, unless: :password_digest?
end
