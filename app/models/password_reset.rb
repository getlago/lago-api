# frozen_string_literal: true

class PasswordReset < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :expire_at, presence: true
end
