# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  validates_presence_of :email, :password
end
