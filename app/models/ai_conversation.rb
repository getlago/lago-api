# frozen_string_literal: true

class AiConversation < ApplicationRecord
  # Bounds how long an unfinished resume keeps the conversation closed to new messages,
  # in case its job never runs. Covers the job's retries.
  RESUME_TIMEOUT = 15.minutes

  belongs_to :membership
  belongs_to :organization

  has_many :tool_calls, class_name: "AiConversationToolCall"

  validates :name, presence: true

  # Between the member's last answer and the end of the resume, the model is still working on
  # the batch: its results, then maybe another round of tool calls.
  def resuming?
    resuming_at.present? && resuming_at > RESUME_TIMEOUT.ago
  end
end

# == Schema Information
#
# Table name: ai_conversations
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  name                    :string           not null
#  resuming_at             :datetime
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
