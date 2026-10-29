# frozen_string_literal: true

class AiConversation < ApplicationRecord
  # Bounds how long an unfinished answer keeps the conversation closed to new messages, in case
  # its job never ends. Covers the resume job's retries.
  BUSY_TIMEOUT = 15.minutes

  belongs_to :membership
  belongs_to :organization

  has_many :tool_calls, class_name: "AiConversationToolCall"

  validates :name, presence: true

  # From a new message, or the member's last answer to the agent's writes, until the agent is done.
  # Meanwhile the model may be waiting for tool results, so it must not get another message.
  def busy?
    busy_at.present? && busy_at > BUSY_TIMEOUT.ago
  end
end

# == Schema Information
#
# Table name: ai_conversations
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  busy_at                 :datetime
#  name                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  membership_id           :uuid             not null
#  mistral_conversation_id :string
#  organization_id         :uuid             not null
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
