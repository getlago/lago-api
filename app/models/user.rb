# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_many :memberships
  has_many :organizations, through: :memberships

  validates_presence_of :email, :password
end
