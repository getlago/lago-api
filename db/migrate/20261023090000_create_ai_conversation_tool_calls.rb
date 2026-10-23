# frozen_string_literal: true

class CreateAiConversationToolCalls < ActiveRecord::Migration[8.1]
  def change
    create_enum :ai_conversation_tool_call_status, %w[pending confirmed cancelled completed]

    create_table :ai_conversation_tool_calls, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid, index: true
      t.references :ai_conversation, null: false, foreign_key: true, type: :uuid, index: false
      t.references :membership, null: false, foreign_key: true, type: :uuid, index: true
      t.string :tool_call_id, null: false
      t.string :name, null: false
      t.jsonb :arguments, null: false, default: {}
      t.enum :status, enum_type: :ai_conversation_tool_call_status, null: false, default: "pending"
      t.boolean :requires_confirmation, null: false, default: false
      t.integer :position, null: false, default: 0
      t.text :result
      t.datetime :decided_at
      t.datetime :submitted_at
      t.timestamps

      t.index [:ai_conversation_id, :submitted_at], name: :index_ai_conversation_tool_calls_on_conversation_and_submitted
    end
  end
end
