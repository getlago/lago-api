# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteOwner, type: :model do
  describe "associations" do
    it "defines the expected associations" do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:quote)
      expect(subject).to belong_to(:user)
    end
  end
end
