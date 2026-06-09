# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Plans::UpdatedDetailsService do
  subject(:webhook_service) { described_class.new(object: plan, options: {changes:}) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:changes) do
    {
      "plan" => {
        "name" => {
          "previous_value" => "Old name",
          "current_value" => "New name"
        }
      }
    }
  end

  describe ".call" do
    it_behaves_like "creates webhook", "plan.updated_details", "plan", {
      "lago_id" => String,
      "code" => String,
      "changes" => Hash
    }

    it "includes the updated details" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload["plan"]["changes"]).to eq(changes)
    end
  end
end
