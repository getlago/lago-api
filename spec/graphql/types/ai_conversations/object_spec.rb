# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AiConversations::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization!")
    expect(subject).to have_field(:conversation_id).of_type("String!")
    expect(subject).to have_field(:input_data).of_type("String!")
    expect(subject).to have_field(:status).of_type("StatusEnum!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
  end
end
