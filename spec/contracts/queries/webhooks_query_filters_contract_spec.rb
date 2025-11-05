# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::WebhooksQueryFiltersContract do
  subject(:result) { described_class.new.call(filters.to_h) }

  let(:filters) { {} }

  context "when filtering by webhook_endpoint_id" do
    let(:filters) { {webhook_endpoint_id: "webhook-123"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when filter is blank" do
      let(:filters) { {webhook_endpoint_id: nil} }

      it "is invalid" do
        expect(result.success?).to be(false)
      end
    end
  end

  context "when filtering by status" do
    let(:filters) { {webhook_endpoint_id: "webhook-123", status: "pending"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when filter is an array" do
      let(:filters) { {webhook_endpoint_id: "webhook-123", status: ["pending", "succeeded"]} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filters are invalid" do
    it_behaves_like "an invalid filter", :status, "random", ["must be one of: pending, succeeded, failed or must be an array"]
    it_behaves_like "an invalid filter", :status, ["pending", "random"], {1 => ["must be one of: pending, succeeded, failed"]}
  end
end
