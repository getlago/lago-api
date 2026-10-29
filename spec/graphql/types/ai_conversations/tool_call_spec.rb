# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AiConversations::ToolCall do
  subject { described_class }

  it do
    expect(subject).to have_field(:arguments).of_type("JSON!")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:status).of_type("AiConversationToolCallStatusEnum!")
    expect(subject).to have_field(:batch_answered).of_type("Boolean!")
  end
end
