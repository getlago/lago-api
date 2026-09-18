# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::AddOns::UpdatedService do
  subject(:webhook_service) { described_class.new(object: add_on) }

  let(:organization) { create(:organization) }
  let(:add_on) { create(:add_on, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "add_on.updated", "add_on", {
      "lago_id" => String,
      "name" => String,
      "code" => String,
      "amount_cents" => Integer
    }
  end
end
