# frozen_string_literal: true

FactoryBot.define do
  factory :ai_conversation_tool_call do
    ai_conversation
    organization { ai_conversation.organization }
    membership { ai_conversation.membership }
    tool_call_id { SecureRandom.hex(8) }
    name { "create_coupon" }
    arguments { {"coupon" => {"code" => "SPRING"}} }
    status { "pending" }
    requires_confirmation { true }
  end
end
