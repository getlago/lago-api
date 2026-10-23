# frozen_string_literal: true

# A tool call the AI agent made in a batch that holds at least one write. The batch waits
# until the member confirms or cancels every write, then all its results go back to the model.
# The row records the member the agent acted for.
class AiConversationToolCall < ApplicationRecord
  STATUSES = {
    pending: "pending",
    confirmed: "confirmed",
    executing: "executing",
    cancelled: "cancelled",
    completed: "completed"
  }.freeze

  belongs_to :organization
  belongs_to :ai_conversation
  belongs_to :membership

  enum :status, STATUSES, validate: true

  validates :tool_call_id, :name, presence: true

  scope :unsubmitted, -> { where(submitted_at: nil) }
end

# == Schema Information
#
# Table name: ai_conversation_tool_calls
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  arguments             :jsonb            not null
#  decided_at            :datetime
#  name                  :string           not null
#  position              :integer          default(0), not null
#  requires_confirmation :boolean          default(FALSE), not null
#  result                :text
#  status                :enum             default("pending"), not null
#  submitted_at          :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  ai_conversation_id    :uuid             not null
#  membership_id         :uuid             not null
#  organization_id       :uuid             not null
#  tool_call_id          :string           not null
#
# Indexes
#
#  index_ai_conversation_tool_calls_on_conversation_and_submitted  (ai_conversation_id,submitted_at)
#  index_ai_conversation_tool_calls_on_membership_id               (membership_id)
#  index_ai_conversation_tool_calls_on_organization_id             (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (ai_conversation_id => ai_conversations.id)
#  fk_rails_...  (membership_id => memberships.id)
#  fk_rails_...  (organization_id => organizations.id)
#
