# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingViesCheck, type: :model do
  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:billing_entity)
      expect(subject).to belong_to(:customer)
    end
  end
end
