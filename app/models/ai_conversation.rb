# frozen_string_literal: true

class AiConversation < ApplicationRecord
  belongs_to :membership
  belongs_to :organization

  validates :conversation_id, presence: true
  validates :input_data, presence: true
  validates :status, presence: true

  STATUS = %w[pending completed].freeze
  enum :status, STATUS.map { |s| [s, s] }.to_h, default: :pending
end

# == Schema Information
#
# Table name: ai_conversations
#
#  id              :uuid             not null, primary key
#  input_data      :string           not null
#  status          :string           default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :string           not null
#  membership_id   :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_ai_conversations_on_membership_id    (membership_id)
#  index_ai_conversations_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (membership_id => memberships.id)
#  fk_rails_...  (organization_id => organizations.id)
#
