# frozen_string_literal: true

class PasswordReset < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :expire_at, presence: true
end

# == Schema Information
#
# Table name: password_resets
#
#  id         :uuid             not null, primary key
#  user_id    :uuid             not null
#  token      :string           not null
#  expire_at  :datetime         not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_password_resets_on_token    (token) UNIQUE
#  index_password_resets_on_user_id  (user_id)
#
