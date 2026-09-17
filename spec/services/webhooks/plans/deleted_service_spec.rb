# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Plans::DeletedService do
  subject(:webhook_service) { described_class.new(object: plan) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "plan.deleted", "plan"

    context "when the object is a catalog plan" do
      subject(:webhook_service) { described_class.new(object: catalog_plan) }

      let(:catalog_plan) { create(:catalog_plan, organization:) }

      it_behaves_like "creates webhook", "plan.deleted", "plan", {
        "code" => String,
        "name" => String,
        "currency" => String
      }
    end
  end
end
