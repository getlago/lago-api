# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_many :memberships
  has_many :organizations, through: :memberships

  has_many :billable_metrics, through: :organizations
  has_many :customers, through: :organizations
  has_many :plans, through: :organizations

  validates_presence_of :email, :password
end
